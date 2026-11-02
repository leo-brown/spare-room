#!/usr/bin/env python3
"""Crashpad API. Python standard library only; all runtime state stays outside source."""
import argparse
from contextlib import closing
import base64
import binascii
import datetime as dt
import hashlib
import hmac
import json
import logging
import os
from pathlib import Path
import re
import secrets
import sqlite3
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

ROOT = Path(__file__).resolve().parent
DB_PATH = os.environ.get('ROOMS_DATABASE', '/var/lib/spare-room/rooms.sqlite3')
PUBLIC = Path(os.environ.get('ROOMS_PUBLIC', str(ROOT.parent / 'public')))

class PhotoResponse:
    def __init__(self, content): self.content = content

class APIError(Exception):
    def __init__(self, status, message):
        self.status, self.message = status, message

def now():
    return dt.datetime.now(dt.timezone.utc).isoformat()

def uid():
    return secrets.token_hex(16)

def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()

def password_hash(value):
    salt = secrets.token_hex(16)
    return salt + ':' + hashlib.pbkdf2_hmac('sha256', value.encode(), salt.encode(), 600000).hex()

def password_matches(value, stored):
    salt, expected = stored.split(':')
    return hmac.compare_digest(expected, hashlib.pbkdf2_hmac('sha256', value.encode(), salt.encode(), 600000).hex())

def connect():
    c = sqlite3.connect(DB_PATH, timeout=15, isolation_level=None)
    c.row_factory = sqlite3.Row
    c.execute('PRAGMA foreign_keys=ON')
    c.execute('PRAGMA busy_timeout=15000')
    return c

def initialize():
    Path(DB_PATH).parent.mkdir(parents=True, exist_ok=True)
    with closing(connect()) as c:
        c.execute('PRAGMA journal_mode=WAL')
        c.executescript((ROOT / 'schema.sql').read_text())
    os.chmod(DB_PATH, 0o600)

def rows(c, sql, args=()):
    return [dict(r) for r in c.execute(sql, args)]

def one(c, sql, args=(), message='Not found'):
    r = c.execute(sql, args).fetchone()
    if r is None:
        raise APIError(404, message)
    return dict(r)

def text(data, key, maximum=200, minimum=1):
    value = data.get(key)
    if not isinstance(value, str) or len(value.strip()) < minimum or len(value.strip()) > maximum:
        raise APIError(400, f'Enter a valid {key.replace("_", " ")} ({minimum}–{maximum} characters).')
    return value.strip()

def integer(data, key, low, high):
    v = data.get(key)
    if type(v) is not int or not low <= v <= high:
        raise APIError(400, f'{key} must be between {low} and {high}.')
    return v

def dates(data):
    try:
        a, b = (dt.date.fromisoformat(data[k]) for k in ('start', 'end'))
    except (ValueError, TypeError, KeyError):
        raise APIError(400, 'Use calendar dates in YYYY-MM-DD format.')
    if a >= b or (b-a).days > 730:
        raise APIError(400, 'Check-out must follow check-in (maximum two years).')
    return a.isoformat(), b.isoformat()

def member(c, network, user):
    return one(c, 'SELECT * FROM memberships WHERE network_id=? AND user_id=?', (network,user), 'Network not found')

def room_for(c, room, user, owner=False):
    r = one(c, 'SELECT * FROM rooms WHERE id=?', (room,))
    member(c, r['network_id'], user)
    if owner and r['owner_id'] != user:
        raise APIError(403, 'Only the host can change this room.')
    return r

def free_nights(c, room, start, end, excluding_stay=None):
    """Explicit free nights, minus busy blocks and accepted stays; check-out is exclusive."""
    blocks = rows(c, 'SELECT start,end,kind FROM periods WHERE room_id=? AND start<? AND end>?', (room,end,start))
    booked = rows(c, "SELECT id,start,end FROM stays WHERE room_id=? AND status='accepted' AND start<? AND end>?", (room,end,start))
    result = []
    day = dt.date.fromisoformat(start)
    while day.isoformat() < end:
        s = day.isoformat()
        available = any(p['kind']=='free' and p['start']<=s<p['end'] for p in blocks)
        blocked = any(p['kind']=='busy' and p['start']<=s<p['end'] for p in blocks)
        blocked |= any(p['id'] != excluding_stay and p['start']<=s<p['end'] for p in booked)
        if available and not blocked:
            result.append(s)
        day += dt.timedelta(days=1)
    return result

def available(c, room, start, end, excluding_stay=None):
    return len(free_nights(c, room,start,end,excluding_stay)) == (dt.date.fromisoformat(end)-dt.date.fromisoformat(start)).days

def event(c, network, actor, kind, title, body, recipient=None):
    c.execute('INSERT INTO events(network_id,actor_id,recipient_id,kind,title,body,created) VALUES(?,?,?,?,?,?,?)', (network,actor,recipient,kind,title,body,now()))

def availability_event(c, room, actor, before, after):
    today=dt.datetime.now(ZoneInfo(room['timezone'])).date().isoformat()
    added = sorted(d for d in set(after)-set(before) if d >= today)
    if added:
        event(c,room['network_id'],actor,'availability','New nights to stay', f'{room["title"]} in {room["city"]}: {len(added)} newly free night(s), from {added[0]}.')

def issue_session(c, user):
    token = secrets.token_urlsafe(48)
    expiry = (dt.datetime.now(dt.timezone.utc)+dt.timedelta(days=180)).isoformat()
    c.execute('INSERT INTO sessions VALUES(?,?,?)', (digest(token), user['id'], expiry))
    return {'token':token, 'user':{k:user[k] for k in ('id','name','email')}}

def limited(c, key, limit=15):
    window = int(time.time())//900
    c.execute('DELETE FROM rate_limits WHERE window<?', (window-2,))
    c.execute('INSERT INTO rate_limits VALUES(?,1,?) ON CONFLICT(key) DO UPDATE SET count=CASE WHEN window=excluded.window THEN count+1 ELSE 1 END,window=excluded.window', (key,window))
    if c.execute('SELECT count FROM rate_limits WHERE key=?', (key,)).fetchone()[0] > limit:
        raise APIError(429, 'Too many attempts. Please try again in 15 minutes.')

class Handler(BaseHTTPRequestHandler):
    server_version = 'Crashpad'
    sys_version = ''
    def log_message(self, fmt, *args):
        # Never log bodies, Authorization headers, network codes, or query parameters.
        logging.info('%s %s', self.command, urlparse(self.path).path)

    def reply(self, status, data):
        body = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header('Content-Type','application/json; charset=utf-8')
        self.send_header('Content-Length',str(len(body)))
        self.send_header('Cache-Control','no-store')
        self.send_header('X-Content-Type-Options','nosniff')
        self.end_headers()
        if not getattr(self,'head_only',False): self.wfile.write(body)

    def do_HEAD(self):
        self.head_only = True
        self.command = 'GET'
        self.handle_request()

    def do_GET(self):
        self.handle_request()
    def do_POST(self):
        self.handle_request()
    def do_DELETE(self):
        self.handle_request()
    def do_PATCH(self):
        self.handle_request()

    def handle_request(self):
        path = urlparse(self.path).path.rstrip('/') or '/'
        if not path.startswith('/api/'):
            if self.command != 'GET':
                return self.reply(405, {'error':'Method not allowed'})
            files = {'/':'index.html','/privacy':'privacy.html','/source.zip':'source.zip'}
            name = files.get(path)
            if not name or not (PUBLIC/name).is_file():
                return self.reply(404, {'error':'Not found'})
            b = (PUBLIC/name).read_bytes()
            self.send_response(200)
            self.send_header('Content-Type','application/zip' if name.endswith('zip') else 'text/html; charset=utf-8')
            self.send_header('Content-Length',str(len(b)))
            self.send_header('X-Content-Type-Options','nosniff')
            self.send_header('Content-Security-Policy',"default-src 'none'; style-src 'unsafe-inline'; img-src 'self' data:; base-uri 'none'; frame-ancestors 'none'")
            self.end_headers()
            if not getattr(self,'head_only',False): self.wfile.write(b)
            return
        c = None
        try:
            length = int(self.headers.get('Content-Length','0'))
            if not 0 <= length <= 1500000:
                raise APIError(413,'Request too large')
            data = json.loads(self.rfile.read(length)) if length else {}
            if not isinstance(data,dict):
                raise APIError(400,'Expected a JSON object')
            c = connect()
            # Serialize mutations, including availability checks, to prevent double bookings.
            c.execute('BEGIN IMMEDIATE' if self.command != 'GET' else 'BEGIN')
            result = self.route(c,path,data)
            c.commit()
            if isinstance(result, PhotoResponse):
                self.send_response(200)
                self.send_header('Content-Type','image/jpeg')
                self.send_header('Content-Length',str(len(result.content)))
                self.send_header('Cache-Control','private, no-store')
                self.send_header('X-Content-Type-Options','nosniff')
                self.end_headers()
                if not getattr(self,'head_only',False): self.wfile.write(result.content)
            else:
                self.reply(200,result)
        except APIError as e:
            if c:
                # Keep rate-limit counters even when authentication fails.
                if path in ('/api/signup','/api/login','/api/recover','/api/networks/join'):
                    c.commit()
                else:
                    c.rollback()
            self.reply(e.status,{'error':e.message})
        except (json.JSONDecodeError, ValueError):
            if c: c.rollback()
            self.reply(400,{'error':'Invalid request'})
        except Exception:
            if c: c.rollback()
            logging.exception('API failure')
            self.reply(500,{'error':'The server could not complete this request.'})
        finally:
            if c: c.close()

    def route(self,c,path,data):
        method = self.command
        if path == '/api/health' and method == 'GET':
            return {'status':'ok','version':1}
        if path in ('/api/signup','/api/login','/api/recover') and method == 'POST':
            # Trust X-Forwarded-For only from the loopback reverse proxy.
            ip = self.headers.get('X-Forwarded-For',self.client_address[0]).split(',')[-1].strip() if self.client_address[0] in ('127.0.0.1','::1') else self.client_address[0]
            limited(c,'auth:'+ip,30)
            email = text(data,'email',254).lower()
            if not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+',email):
                raise APIError(400,'Enter a valid email address.')
            password = text(data,'password',200,10)
            if path == '/api/signup':
                name = text(data,'name',80)
                if c.execute('SELECT 1 FROM users WHERE email=?',(email,)).fetchone():
                    raise APIError(409,'This email is already registered. Sign in or recover your account.')
                recovery = secrets.token_urlsafe(24)
                user = {'id':uid(),'name':name,'email':email}
                c.execute('INSERT INTO users VALUES(?,?,?,?,?,?)',(user['id'],name,email,password_hash(password),digest(recovery),now()))
                return {**issue_session(c,user),'recovery_key':recovery}
            user = c.execute('SELECT * FROM users WHERE email=?',(email,)).fetchone()
            if path == '/api/login':
                if not password_matches(password, user['password'] if user else '0'*32+':'+'0'*64):
                    raise APIError(401,'Email or password is incorrect.')
            else:
                key = text(data,'recovery_key',100)
                if not user or not hmac.compare_digest(digest(key),user['recovery_hash']):
                    raise APIError(401,'Email or recovery key is incorrect.')
                c.execute('UPDATE users SET password=? WHERE id=?',(password_hash(password),user['id']))
                c.execute('DELETE FROM sessions WHERE user_id=?',(user['id'],))
            return issue_session(c,dict(user))
        auth = self.headers.get('Authorization','')
        if not auth.startswith('Bearer '):
            raise APIError(401,'Please sign in.')
        user = c.execute('SELECT u.* FROM users u JOIN sessions s ON s.user_id=u.id WHERE s.token_hash=? AND s.expires>?',(digest(auth[7:]),now())).fetchone()
        if not user: raise APIError(401,'Your session has expired. Please sign in.')
        user = dict(user)
        u = user['id']
        if path == '/api/logout' and method == 'POST':
            c.execute('DELETE FROM sessions WHERE token_hash=?',(digest(auth[7:]),))
            return {'ok':True}
        if path == '/api/account' and method == 'DELETE':
            if not password_matches(text(data,'password',200,10),user['password']):
                raise APIError(403,'Password is incorrect.')
            if c.execute('SELECT 1 FROM memberships m JOIN networks n ON n.id=m.network_id WHERE n.owner_id=? AND m.user_id!=? LIMIT 1',(u,u)).fetchone():
                raise APIError(409,'Remove other members or delete your networks before deleting your account.')
            c.execute('DELETE FROM events WHERE actor_id=? OR recipient_id=?',(u,u))
            c.execute('DELETE FROM users WHERE id=?',(u,))
            return {'ok':True}
        if path == '/api/snapshot' and method == 'GET':
            networks = rows(c,'SELECT n.*,m.muted FROM networks n JOIN memberships m ON n.id=m.network_id WHERE m.user_id=? ORDER BY n.name',(u,))
            rooms = rows(c,'SELECT r.*,u.name AS host_name FROM rooms r JOIN users u ON u.id=r.owner_id JOIN memberships m ON m.network_id=r.network_id WHERE m.user_id=? ORDER BY r.city,r.title',(u,))
            periods = rows(c,'SELECT p.* FROM periods p JOIN rooms r ON r.id=p.room_id JOIN memberships m ON m.network_id=r.network_id WHERE m.user_id=?',(u,))
            stays = rows(c,'SELECT s.*,u.name AS guest_name,r.title AS room_title,r.owner_id AS host_id,r.network_id FROM stays s JOIN users u ON u.id=s.guest_id JOIN rooms r ON r.id=s.room_id JOIN memberships m ON m.network_id=r.network_id WHERE m.user_id=? AND (s.guest_id=? OR r.owner_id=?) ORDER BY s.created DESC',(u,u,u))
            # Calendar occupancy is visible within the network; guest identities/messages are private to host and guest.
            bookings = rows(c,"SELECT s.id,s.room_id,s.start,s.end FROM stays s JOIN rooms r ON r.id=s.room_id JOIN memberships m ON m.network_id=r.network_id WHERE m.user_id=? AND s.status='accepted'",(u,))
            members = rows(c,'SELECT m.network_id,u.id,u.name FROM memberships m JOIN users u ON u.id=m.user_id WHERE m.network_id IN (SELECT network_id FROM memberships WHERE user_id=?) ORDER BY u.name',(u,))
            photos = rows(c,'SELECT p.id,p.room_id FROM photos p JOIN rooms r ON r.id=p.room_id JOIN memberships m ON m.network_id=r.network_id WHERE m.user_id=? ORDER BY p.rowid',(u,))
            return {'photos':photos,'user':{k:user[k] for k in ('id','name','email')},'networks':networks,'rooms':rooms,'periods':periods,'stays':stays,'bookings':bookings,'members':members,'cursor':c.execute('SELECT COALESCE(MAX(id),0) FROM events').fetchone()[0]}
        if path == '/api/events' and method == 'GET':
            try: after = max(0,int(parse_qs(urlparse(self.path).query).get('after',['0'])[0]))
            except ValueError: raise APIError(400,'Invalid event cursor')
            events = rows(c,'SELECT e.* FROM events e JOIN memberships m ON m.network_id=e.network_id WHERE m.user_id=? AND e.id>? AND e.id>m.joined_event AND e.actor_id IS NOT ? AND (e.recipient_id IS NULL OR e.recipient_id=?) AND m.muted=0 ORDER BY e.id LIMIT 100',(u,after,u,u))
            cursor = events[-1]['id'] if len(events)==100 else c.execute('SELECT COALESCE(MAX(id),0) FROM events').fetchone()[0]
            return {'events':events,'cursor':cursor}
        if path == '/api/networks' and method == 'POST':
            limited(c,'network-create:'+u,20)
            n = uid()
            code = ''.join(secrets.choice('ABCDEFGHJKLMNPQRSTUVWXYZ23456789') for _ in range(10))
            c.execute('INSERT INTO networks VALUES(?,?,?,?)',(n,text(data,'name',80),code,u))
            c.execute('INSERT INTO memberships(network_id,user_id) VALUES(?,?)',(n,u))
            return {'id':n,'code':code}
        if path == '/api/networks/join' and method == 'POST':
            limited(c,'join:'+u,15)
            code = text(data,'code',30).upper().replace('-','').replace(' ','')
            n = one(c,'SELECT * FROM networks WHERE code=?',(code,),'That network code was not found.')
            cursor = c.execute('SELECT COALESCE(MAX(id),0) FROM events').fetchone()[0]
            c.execute('INSERT OR IGNORE INTO memberships(network_id,user_id,joined_event) VALUES(?,?,?)',(n['id'],u,cursor))
            return {'id':n['id']}
        match = re.fullmatch(r'/api/networks/([a-f0-9]+)/?(rotate|leave|mute|members)?/?([a-f0-9]+)?',path)
        if match:
            n, action, target = match.groups()
            m = member(c,n,u)
            net = one(c,'SELECT * FROM networks WHERE id=?',(n,))
            if action=='mute' and method=='POST':
                c.execute('UPDATE memberships SET muted=? WHERE network_id=? AND user_id=?',(int(bool(data.get('muted'))),n,u))
                return {'ok':True}
            if action=='leave' and method=='POST':
                if net['owner_id']==u: raise APIError(409,'The network owner must delete the network instead.')
                self.remove_member(c,n,u)
                return {'ok':True}
            if net['owner_id']!=u: raise APIError(403,'Only the network owner can do that.')
            if action=='rotate' and method=='POST':
                code = ''.join(secrets.choice('ABCDEFGHJKLMNPQRSTUVWXYZ23456789') for _ in range(10))
                c.execute('UPDATE networks SET code=? WHERE id=?',(code,n))
                return {'code':code}
            if action=='members' and target and method=='DELETE':
                if target==u: raise APIError(400,'You cannot remove yourself as owner.')
                self.remove_member(c,n,target)
                return {'ok':True}
            if action is None and method=='DELETE':
                c.execute('DELETE FROM networks WHERE id=?',(n,))
                return {'ok':True}
        if path == '/api/rooms' and method=='POST':
            n = text(data,'network_id',32)
            member(c,n,u)
            r = uid()
            fields = self.room_fields(data)
            c.execute('INSERT INTO rooms VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',(r,n,u,*fields))
            return {'id':r}
        match = re.fullmatch(r'/api/rooms/([a-f0-9]+)(/periods|/photos)?',path)
        if match:
            rid, action = match.groups()
            r = room_for(c,rid,u,True)
            if action is None and method=='PATCH':
                if c.execute("SELECT 1 FROM stays WHERE room_id=? AND status='accepted' AND guests>?",(rid,integer(data,'guests',1,20))).fetchone():
                    raise APIError(409,'The guest limit must cover your accepted stays.')
                c.execute('UPDATE rooms SET title=?,street=?,city=?,postal_code=?,country=?,timezone=?,description=?,guests=?,room_type=? WHERE id=?',(*self.room_fields(data),rid))
                return {'ok':True}
            if action is None and method=='DELETE':
                c.execute('DELETE FROM rooms WHERE id=?',(rid,))
                return {'ok':True}
            if action == '/photos' and method == 'POST':
                if c.execute('SELECT COUNT(*) FROM photos WHERE room_id=?',(rid,)).fetchone()[0] >= 8:
                    raise APIError(400,'A listing can have up to eight photos.')
                try: content = base64.b64decode(data.get('image',''),validate=True)
                except (binascii.Error,TypeError): raise APIError(400,'Invalid photo.')
                if len(content)>1000000 or len(content)<4 or not content.startswith(b'\xff\xd8\xff') or not content.endswith(b'\xff\xd9'):
                    raise APIError(400,'Choose a JPEG photo smaller than 1 MB.')
                pid=uid()
                c.execute('INSERT INTO photos VALUES(?,?,?)',(pid,rid,content))
                return {'id':pid}
            if action == '/periods' and method=='POST':
                a,b = dates(data)
                if b <= dt.datetime.now(ZoneInfo(r['timezone'])).date().isoformat(): raise APIError(400,'Choose current or future dates.')
                kind = text(data,'kind',4)
                if kind not in ('free','busy'): raise APIError(400,'Choose free or busy.')
                if kind=='busy' and c.execute("SELECT 1 FROM stays WHERE room_id=? AND status='accepted' AND start<? AND end>?",(rid,b,a)).fetchone():
                    raise APIError(409,'Cancel the accepted stay before marking those nights busy.')
                before = free_nights(c,rid,a,b)
                p = uid()
                c.execute('INSERT INTO periods VALUES(?,?,?,?,?)',(p,rid,a,b,kind))
                availability_event(c,r,u,before,free_nights(c,rid,a,b))
                return {'id':p}
        photo = re.fullmatch(r'/api/photos/([a-f0-9]+)',path)
        if photo:
            p = one(c,'SELECT * FROM photos WHERE id=?',(photo[1],))
            room_for(c,p['room_id'],u,method=='DELETE')
            if method=='GET': return PhotoResponse(p['content'])
            if method=='DELETE':
                c.execute('DELETE FROM photos WHERE id=?',(p['id'],))
                return {'ok':True}
        match = re.fullmatch(r'/api/periods/([a-f0-9]+)',path)
        if match and method=='DELETE':
            p = one(c,'SELECT * FROM periods WHERE id=?',(match[1],))
            r = room_for(c,p['room_id'],u,True)
            if p['kind']=='free' and c.execute("SELECT 1 FROM stays WHERE room_id=? AND status='accepted' AND start<? AND end>?",(r['id'],p['end'],p['start'])).fetchone():
                raise APIError(409,'Cancel the accepted stay before removing its free dates.')
            before = free_nights(c,r['id'],p['start'],p['end'])
            c.execute('DELETE FROM periods WHERE id=?',(p['id'],))
            availability_event(c,r,u,before,free_nights(c,r['id'],p['start'],p['end']))
            return {'ok':True}
        if path=='/api/stays' and method=='POST':
            r = room_for(c,text(data,'room_id',32),u)
            if r['owner_id']==u: raise APIError(400,'You cannot request your own room.')
            a,b=dates(data)
            if a < dt.datetime.now(ZoneInfo(r['timezone'])).date().isoformat(): raise APIError(400,'Check-in cannot be in the past.')
            guests=integer(data,'guests',1,r['guests'])
            if not available(c,r['id'],a,b): raise APIError(409,'This room is no longer free for all of those nights.')
            if c.execute("SELECT 1 FROM stays WHERE room_id=? AND guest_id=? AND start=? AND end=? AND status IN ('pending','accepted')",(r['id'],u,a,b)).fetchone(): raise APIError(409,'You already requested these dates.')
            sid=uid()
            c.execute('INSERT INTO stays VALUES(?,?,?,?,?,?,?,?,?)',(sid,r['id'],u,a,b,guests,text(data,'message',2000,0),'pending',now()))
            event(c,r['network_id'],u,'request','A new stay request',f'{user["name"]} would like to stay at {r["title"]}, {a} to {b}.',r['owner_id'])
            return {'id':sid}
        match = re.fullmatch(r'/api/stays/([a-f0-9]+)',path)
        if match and method=='POST':
            s=one(c,'SELECT * FROM stays WHERE id=?',(match[1],))
            r=room_for(c,s['room_id'],u)
            status=text(data,'status',20)
            host=r['owner_id']==u
            if status in ('accepted','declined') and host and s['status']=='pending':
                if status=='accepted' and (s['start'] < dt.datetime.now(ZoneInfo(r['timezone'])).date().isoformat() or not available(c,r['id'],s['start'],s['end'])): raise APIError(409,'Those dates are no longer available.')
                c.execute('UPDATE stays SET status=? WHERE id=?',(status,s['id']))
                event(c,r['network_id'],u,'request','Stay request '+status,f'{r["title"]}: {s["start"]} to {s["end"]}.',s['guest_id'])
                if status=='accepted':
                    overlaps=rows(c,"SELECT * FROM stays WHERE room_id=? AND status='pending' AND start<? AND end>?",(r['id'],s['end'],s['start']))
                    for other in overlaps:
                        c.execute("UPDATE stays SET status='declined' WHERE id=?",(other['id'],))
                        event(c,r['network_id'],u,'request','Dates no longer available',f'Your request for {r["title"]} was declined because another stay was accepted.',other['guest_id'])
                return {'ok':True}
            if status=='cancelled' and (host or s['guest_id']==u) and s['status'] in ('pending','accepted'):
                before=free_nights(c,r['id'],s['start'],s['end'])
                c.execute("UPDATE stays SET status='cancelled' WHERE id=?",(s['id'],))
                recipient=s['guest_id'] if host else r['owner_id']
                event(c,r['network_id'],u,'request','Stay cancelled',f'{r["title"]}: {s["start"]} to {s["end"]}.',recipient)
                availability_event(c,r,u,before,free_nights(c,r['id'],s['start'],s['end']))
                return {'ok':True}
            raise APIError(403,'This stay cannot be changed in that way.')
        raise APIError(404,'Endpoint not found')

    def room_fields(self,data):
        tz=text(data,'timezone',100)
        try: ZoneInfo(tz)
        except ZoneInfoNotFoundError: raise APIError(400,'Choose a valid time zone.')
        kind=text(data,'room_type',10)
        if kind not in ('room','home','van'): raise APIError(400,'Choose room, home or van.')
        return (text(data,'title',100),text(data,'street',150),text(data,'city',100),text(data,'postal_code',20),text(data,'country',80),tz,text(data,'description',2000,0),integer(data,'guests',1,20),kind)

    def remove_member(self,c,network,user):
        # A departed member must lose both listing and guest access in this network.
        c.execute('DELETE FROM stays WHERE guest_id=? AND room_id IN (SELECT id FROM rooms WHERE network_id=?)',(user,network))
        c.execute('DELETE FROM rooms WHERE owner_id=? AND network_id=?',(user,network))
        c.execute('DELETE FROM memberships WHERE network_id=? AND user_id=?',(network,user))

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--port',type=int,default=8791)
    parser.add_argument('--host',default='127.0.0.1')
    args=parser.parse_args()
    logging.basicConfig(level=logging.INFO)
    initialize()
    ThreadingHTTPServer((args.host,args.port),Handler).serve_forever()
