"""Isolated HTTP acceptance tests. Never contacts production or uses real personal data."""
import base64
from contextlib import closing
import concurrent.futures
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer

spec = importlib.util.spec_from_file_location('rooms',Path(__file__).resolve().parents[1]/'backend/server.py')
api = importlib.util.module_from_spec(spec)
spec.loader.exec_module(api)

class AcceptanceTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        api.DB_PATH=self.tmp.name+'/rooms.sqlite3'
        api.initialize()
        self.server=ThreadingHTTPServer(('127.0.0.1',0),api.Handler)
        self.thread=threading.Thread(target=self.server.serve_forever,daemon=True); self.thread.start()
        self.url=f'http://127.0.0.1:{self.server.server_port}/api/'
        self.host=self.signup('host')
        self.guest=self.signup('guest')
        self.outsider=self.signup('outsider')
        _, self.network=self.request('networks',self.host,{'name':'Test network'})
        self.nid=self.network['id']
        self.request('networks/join',self.guest,{'code':self.network['code']})
        status,room=self.request('rooms',self.host,self.room_body())
        self.assertEqual(status,200,room)
        self.rid=room['id']
    def tearDown(self):
        self.server.shutdown(); self.server.server_close(); self.thread.join(); self.tmp.cleanup()
    def signup(self,name):
        status,auth=self.request('signup',body={'name':name,'email':name+'@example.invalid','password':'test-password-123'})
        self.assertEqual(status,200,auth)
        return auth
    def request(self,path,user=None,body=None,method=None):
        headers={'Content-Type':'application/json'}
        if user: headers['Authorization']='Bearer '+user['token']
        req=urllib.request.Request(self.url+path,data=json.dumps(body).encode() if body is not None else None,headers=headers,method=method or ('POST' if body is not None else 'GET'))
        try:
            with urllib.request.urlopen(req,timeout=10) as response:
                b=response.read()
                return response.status,b if response.headers.get_content_type()=='image/jpeg' else json.loads(b)
        except urllib.error.HTTPError as e:
            status=e.code
            with e: data=json.loads(e.read())
            return status,data
    def room_body(self):
        return {'network_id':self.nid,'title':'Test room','street':'Example Street','city':'Test City','postal_code':'AB1 2CD','country':'Test Country','timezone':'Europe/London','description':'A test listing','guests':2,'room_type':'room'}
    def period(self,kind='free',start='2027-02-01',end='2027-02-10'):
        status,result=self.request('rooms/'+self.rid+'/periods',self.host,{'kind':kind,'start':start,'end':end})
        self.assertEqual(status,200,result)
        return result['id']
    def stay(self,user=None,start='2027-02-02',end='2027-02-04'):
        return self.request('stays',user or self.guest,{'room_id':self.rid,'start':start,'end':end,'guests':1,'message':'Test stay'})
    def state(self,user=None):
        status,s=self.request('snapshot',user or self.host); self.assertEqual(status,200,s); return s
    def events(self,user=None,after=0):
        status,e=self.request('events?after='+str(after),user or self.guest); self.assertEqual(status,200,e); return e
    def test_network_isolation_and_host_permissions(self):
        self.assertEqual(self.state(self.outsider)['rooms'],[])
        self.assertEqual(self.request('rooms/'+self.rid,self.outsider,method='DELETE')[0],404)
        self.assertEqual(self.request('rooms/'+self.rid,self.guest,method='DELETE')[0],403)
        self.assertEqual(self.request('rooms/'+self.rid+'/periods',self.guest,{'kind':'free','start':'2027-02-01','end':'2027-02-03'})[0],403)
        self.assertEqual(self.request('networks/'+self.nid+'/rotate',self.guest,{})[0],403)
    def test_free_busy_precedence_and_notifications(self):
        self.period()
        self.assertEqual(len(self.events()['events']),1)
        self.period()  # Duplicate free blocks must not generate spurious notifications.
        self.assertEqual(len(self.events()['events']),1)
        p=self.period('busy','2027-02-02','2027-02-04')
        self.assertEqual(self.stay()[0],409)
        self.assertEqual(len(self.events()['events']),1)
        self.assertEqual(self.request('periods/'+p,self.host,method='DELETE')[0],200)
        self.assertEqual(len(self.events()['events']),2)
        self.assertEqual(self.stay()[0],200)
        self.assertEqual(self.events(self.host)['events'][0]['kind'],'request')
    def test_acceptance_prevents_double_booking_and_declines_overlaps(self):
        self.period()
        _,first=self.stay()
        self.request('networks/join',self.outsider,{'code':self.network['code']})
        _,second=self.stay(self.outsider)
        self.assertEqual(self.request('stays/'+first['id'],self.host,{'status':'accepted'})[0],200)
        stays=self.state()['stays']
        self.assertEqual(next(s for s in stays if s['id']==second['id'])['status'],'declined')
        self.assertEqual(self.stay(self.outsider)[0],409)
        self.assertEqual(self.request('rooms/'+self.rid+'/periods',self.host,{'kind':'busy','start':'2027-02-02','end':'2027-02-04'})[0],409)
        # Back-to-back nights are allowed: check-out is exclusive.
        self.assertEqual(self.stay(self.outsider,'2027-02-04','2027-02-05')[0],200)
        self.assertEqual(len(self.state(self.outsider)['bookings']),1)
        self.assertFalse(any(s['id']==first['id'] for s in self.state(self.outsider)['stays']))
    def test_concurrent_acceptance_serialized(self):
        self.period()
        _,a=self.stay()
        self.request('networks/join',self.outsider,{'code':self.network['code']})
        _,b=self.stay(self.outsider)
        with concurrent.futures.ThreadPoolExecutor() as pool:
            results=list(pool.map(lambda sid:self.request('stays/'+sid,self.host,{'status':'accepted'})[0],[a['id'],b['id']]))
        self.assertEqual(results.count(200),1)
        self.assertEqual(len(self.state()['bookings']),1)
    def test_cancellation_reopens_dates(self):
        self.period(); _,s=self.stay()
        self.request('stays/'+s['id'],self.host,{'status':'accepted'})
        cursor=self.events()['cursor']
        self.assertEqual(self.request('stays/'+s['id'],self.host,{'status':'cancelled'})[0],200)
        self.assertEqual(self.state()['bookings'],[])
        self.assertTrue(any(e['kind']=='availability' for e in self.events(after=cursor)['events']))
        self.assertEqual(self.stay()[0],200)
    def test_rotation_removal_and_join_baseline(self):
        self.period()
        _,rotated=self.request('networks/'+self.nid+'/rotate',self.host,{})
        self.assertNotEqual(rotated['code'],self.network['code'])
        self.assertEqual(self.request('networks/join',self.outsider,{'code':self.network['code']})[0],404)
        self.assertEqual(self.request('networks/join',self.outsider,{'code':rotated['code']})[0],200)
        self.assertEqual(self.events(self.outsider)['events'],[])
        self.assertEqual(self.request('networks/'+self.nid+'/members/'+self.guest['user']['id'],self.host,method='DELETE')[0],200)
        self.assertEqual(self.state(self.guest)['rooms'],[])
        self.assertEqual(self.events()['events'],[])
    def test_network_mute(self):
        self.request('networks/'+self.nid+'/mute',self.guest,{'muted':True})
        self.period()
        self.assertEqual(self.events()['events'],[])
    def test_dates_capacity_and_self_request(self):
        self.period('free','2027-02-01','2027-02-03')
        self.assertEqual(self.stay()[0],409)  # Last night not offered.
        self.assertEqual(self.stay(start='2027-02-01',end='2027-02-03')[0],200)
        self.assertEqual(self.stay(self.host,start='2027-02-01',end='2027-02-03')[0],400)
        self.assertEqual(self.request('stays',self.guest,{'room_id':self.rid,'start':'2027-02-01','end':'2027-02-02','guests':3,'message':''})[0],400)
        self.assertEqual(self.stay(start='2027-02-04',end='2027-02-04')[0],400)
        self.assertEqual(self.stay(start='2027-02-30',end='2027-03-01')[0],400)
        self.assertEqual(self.stay(start='2020-01-01',end='2020-01-02')[0],400)
    def test_photo_privacy_and_multiple_places(self):
        image=b'\xff\xd8\xff\xe0test\xff\xd9'
        status,photo=self.request('rooms/'+self.rid+'/photos',self.host,{'image':base64.b64encode(image).decode()})
        self.assertEqual(status,200,photo)
        self.assertEqual(self.request('photos/'+photo['id'],self.guest),(200,image))
        self.assertEqual(self.request('photos/'+photo['id'],self.outsider)[0],404)
        self.assertEqual(self.request('photos/'+photo['id'],self.guest,method='DELETE')[0],403)
        self.assertEqual(self.request('rooms/'+self.rid+'/photos',self.host,{'image':'bad!'})[0],400)
        self.assertEqual(self.request('rooms',self.host,{**self.room_body(),'room_type':'van','title':'Test van'})[0],200)
        self.assertEqual(self.request('rooms',self.host,{**self.room_body(),'title':'Second guest room'})[0],200)
        self.assertEqual(len(self.state()['rooms']),3)
        self.assertEqual(self.request('rooms/'+self.rid,self.host,method='DELETE')[0],200)
        self.assertEqual(self.request('photos/'+photo['id'],self.guest)[0],404)
    def test_recovery_revocation_and_delete(self):
        old=self.guest
        status,new=self.request('recover',body={'email':'guest@example.invalid','password':'replacement-password','recovery_key':old['recovery_key']})
        self.assertEqual(status,200,new)
        self.assertEqual(self.request('snapshot',old)[0],401)
        self.assertEqual(self.request('login',body={'email':'guest@example.invalid','password':'test-password-123'})[0],401)
        self.assertEqual(self.request('account',new,{'password':'replacement-password'},method='DELETE')[0],200)
        self.assertEqual(self.request('snapshot',new)[0],401)
        self.assertEqual(self.request('account',self.host,{'password':'test-password-123'},method='DELETE')[0],200)
    def test_auth_and_invalid_inputs(self):
        self.assertEqual(self.request('snapshot')[0],401)
        self.assertEqual(self.request('login',body={'email':'nobody@example.invalid','password':'not-correct-123'})[0],401)
        self.assertEqual(self.request('rooms',self.host,{**self.room_body(),'timezone':'Not/AZone'})[0],400)
        self.assertEqual(self.request('rooms',self.host,{**self.room_body(),'room_type':'not-valid'})[0],400)
        self.assertEqual(self.request('events?after=invalid',self.host)[0],400)
    def test_event_feed_pagination(self):
        with closing(api.connect()) as c:
            for i in range(105): api.event(c,self.nid,self.host['user']['id'],'availability','Test','Test')
        first=self.events(); self.assertEqual(len(first['events']),100)
        second=self.events(after=first['cursor']); self.assertEqual(len(second['events']),5)
        self.assertGreater(second['cursor'],first['cursor'])

if __name__=='__main__': unittest.main(verbosity=2)
