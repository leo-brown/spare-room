import SwiftUI
import PhotosUI

enum Palette {
    static let accent = Color(uiColor:UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red:0.62,green:0.80,blue:0.69,alpha:1) : UIColor(red:0.14,green:0.38,blue:0.31,alpha:1)
    })
    static let paper = Color(uiColor:UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red:0.08,green:0.12,blue:0.10,alpha:1) : UIColor(red:0.97,green:0.96,blue:0.92,alpha:1)
    })
}
private let forest = Palette.accent
private let sand = Palette.paper

@MainActor private func dismissKeyboard() { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil) }

struct RootView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        ZStack {
            if !store.signedIn { AuthView() }
            else if store.snapshot == nil {
                VStack(spacing:20) {
                    Image(systemName:"house.and.flag.fill").font(.system(size:48)).foregroundStyle(forest)
                    Text("Finding your people…").font(.title2)
                    if store.working { ProgressView() }
                    else { Button("Try again") { Task { await store.refresh() } }; Button("Sign out") { store.clearSession() } }
                }
            } else {
                TabView {
                    DiscoverView().tabItem { Label("Explore",systemImage:"globe.europe.africa") }
                    NetworkCalendarView().tabItem { Label("Calendar",systemImage:"calendar") }
                    HostingView().tabItem { Label("My places",systemImage:"house") }
                    StaysView().tabItem { Label("Stays",systemImage:"suitcase") }
                    NetworksView().tabItem { Label("Networks",systemImage:"person.3") }
                }
            }
        }.sheet(isPresented:$store.needsRecoverySave) {
            NavigationStack {
                VStack(alignment:.leading,spacing:24) {
                    Image(systemName:"key.fill").font(.largeTitle).foregroundStyle(forest)
                    Text("Keep your way home.").font(.system(.largeTitle,design:.serif))
                    Text("Save this recovery key somewhere private. You’ll need it to reset a forgotten password. We don’t send reset emails.")
                    Text(store.recoveryKey ?? "").font(.system(.body,design:.monospaced)).textSelection(.enabled).padding().background(sand,in:RoundedRectangle(cornerRadius:12))
                    if let key=store.recoveryKey { ShareLink(item:key) { Label("Save recovery key",systemImage:"square.and.arrow.up") }.buttonStyle(.bordered) }
                    Button("I’ve saved my key") { store.needsRecoverySave=false }.buttonStyle(.borderedProminent)
                    Spacer()
                }.padding(28).navigationTitle("Account recovery").navigationBarTitleDisplayMode(.inline)
            }.interactiveDismissDisabled()
        }
    }
}

struct AuthView: View {
    @EnvironmentObject var store: Store
    @State private var mode = "signup"
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var recovery = ""
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:24) {
                    HStack { Image(systemName:"door.left.hand.open").font(.system(size:36)); Text("spare room").font(.title2.weight(.semibold)) }.foregroundStyle(forest).padding(.top,32)
                    Text("There’s a place\nfor you.").font(.system(size:46,weight:.medium,design:.serif)).fixedSize(horizontal:false,vertical:true)
                    Text("A little closer to your people. Share a spare room, a home or a van with the networks you trust.").font(.title3).foregroundStyle(.secondary)
                    Picker("Account",selection:$mode) { Text("Get started").tag("signup"); Text("Sign in").tag("login"); Text("Recover").tag("recover") }.pickerStyle(.segmented)
                    VStack(spacing:14) {
                        if mode == "signup" { TextField("Your name",text:$name).textContentType(.name) }
                        TextField("Email",text:$email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        if mode == "recover" { TextField("Recovery key",text:$recovery).textInputAutocapitalization(.never).autocorrectionDisabled() }
                        SecureField(mode == "recover" ? "New password (10+ characters)" : "Password (10+ characters)",text:$password).textContentType(mode == "login" ? .password : .newPassword)
                    }.padding(20).background(.background,in:RoundedRectangle(cornerRadius:18))
                    Button {
                        Task { await store.authenticate(mode,name:name,email:email,password:password,recovery:recovery) }
                    } label: { HStack { Spacer(); if store.working { ProgressView().tint(.white) }; Text(mode == "signup" ? "Make yourself at home" : mode == "recover" ? "Reset password" : "Welcome back"); Spacer(); Image(systemName:"arrow.right") }.padding(10) }.buttonStyle(.borderedProminent).disabled(store.working || email.isEmpty || password.count < 10 || (mode == "signup" && name.trimmingCharacters(in:.whitespaces).isEmpty))
                    Text(mode == "recover" ? "Use the recovery key saved when you created your account. No reset emails are sent." : "Your places are visible only to your networks. Save your recovery key after signing up.").font(.footnote).foregroundStyle(.secondary)
                    Link("Privacy & source code",destination:URL(string:"https://rooms.leobrown.co.uk/privacy")!).font(.footnote)
                }.padding(26)
            }.background(sand).navigationBarHidden(true)
        }
    }
}

struct NetworkPicker: View {
    @EnvironmentObject var store: Store
    var body: some View {
        if let networks = store.snapshot?.networks, !networks.isEmpty {
            Picker("Network",selection:$store.selectedNetwork) {
                ForEach(networks) { Text($0.name).tag($0.id) }
            }.pickerStyle(.menu).padding(.horizontal,8).background(forest.opacity(0.07),in:Capsule())
        }
    }
}
struct EmptyState: View {
    let title: String; let message: String; var icon = "house.and.flag"
    var body: some View { ContentUnavailableView(title,systemImage:icon,description:Text(message)).padding(.vertical,24) }
}

struct DiscoverView: View {
    @EnvironmentObject var store: Store
    @State private var search = ""
    @State private var dates = false
    @State private var start = Date()
    @State private var end = Date().addingDays(1)
    @State private var guests = 1
    var rooms: [Room] {
        guard let s = store.snapshot else { return [] }
        return s.rooms.filter { r in
            r.networkId == store.selectedNetwork && r.guests >= guests &&
            (search.isEmpty || "\(r.title) \(r.city) \(r.country) \(r.postalCode)".localizedCaseInsensitiveContains(search)) &&
            (!dates || s.isFree(r,start:start,end:end))
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    HStack { Text("YOUR PEOPLE. YOUR PLACES.").font(.caption.weight(.bold)).tracking(2).foregroundStyle(forest); Spacer(); NetworkPicker() }
                    Text("Somewhere\nto feel at home.").font(.system(size:38,weight:.medium,design:.serif))
                    VStack(alignment:.leading,spacing:14) {
                        HStack { Image(systemName:"magnifyingglass"); TextField("A city, country or place…",text:$search).autocorrectionDisabled() }
                        Divider()
                        Toggle("Find free dates",isOn:$dates)
                        if dates { DateRangeFields(start:$start,end:$end) }
                        Stepper("\(guests) guest\(guests == 1 ? "" : "s")",value:$guests,in:1...20)
                    }.padding(18).background(.background,in:RoundedRectangle(cornerRadius:18))
                    if store.snapshot?.networks.isEmpty == true {
                        EmptyState(title:"Start with your people",message:"Create a network or join with a shared code in the Networks tab.",icon:"person.3")
                    } else if rooms.isEmpty {
                        EmptyState(title:"Room for possibilities",message:dates ? "No places are free for every selected night. Try other dates or another network." : "No places match yet. Share your network code and add the first place.")
                    } else {
                        HStack { Text("Places to reconnect").font(.title2.weight(.semibold)); Spacer(); Text("\(rooms.count)").foregroundStyle(.secondary) }
                        ForEach(rooms) { room in NavigationLink { RoomDetailView(roomId:room.id,initialStart:start,initialEnd:end) } label: { RoomCard(room:room) }.buttonStyle(.plain) }
                    }
                }.padding(22)
            }.background(sand).navigationTitle("Spare Room").navigationBarTitleDisplayMode(.inline)
                .refreshable { await store.refresh() }
        }
    }
}

struct RoomPhoto: View {
    @EnvironmentObject var store: Store
    let photoId: String
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            forest.opacity(0.12)
            if let image { Image(uiImage:image).resizable().scaledToFill() }
            else { Image(systemName:"photo").font(.largeTitle).foregroundStyle(forest.opacity(0.4)) }
        }.clipped().task(id:photoId) {
            if let data = try? await store.call("photos/\(photoId)"), let photo = UIImage(data:data) { image = photo }
        }
    }
}
struct RoomCard: View {
    @EnvironmentObject var store: Store
    let room: Room
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            ZStack(alignment:.bottomLeading) {
                if let photo = store.snapshot?.photos.first(where:{$0.roomId == room.id}) {
                    RoomPhoto(photoId:photo.id).frame(height:200).clipped()
                } else {
                    Rectangle().fill(LinearGradient(colors:[forest.opacity(0.2),forest.opacity(0.06)],startPoint:.topLeading,endPoint:.bottomTrailing)).frame(height:180)
                    Image(systemName:room.roomType == "van" ? "car.side" : "door.left.hand.open").font(.system(size:60,weight:.ultraLight)).foregroundStyle(forest).frame(maxWidth:.infinity,maxHeight:.infinity)
                }
                Text(room.roomType == "van" ? "VAN LIFE" : room.roomType == "home" ? "A HOME TO SHARE" : "A ROOM FOR YOU").font(.caption2.weight(.bold)).tracking(1.5).padding(9).background(.regularMaterial,in:Capsule()).padding(14)
            }
            VStack(alignment:.leading,spacing:7) {
                HStack { Text(room.title).font(.title3.weight(.semibold)); Spacer(); Image(systemName:"arrow.up.right").foregroundStyle(forest) }
                Text(room.location).foregroundStyle(.secondary)
                HStack { Label(room.hostName,systemImage:"person.crop.circle"); Spacer(); Text("Up to \(room.guests) guests") }.font(.caption).foregroundStyle(.secondary)
            }.padding(16)
        }.background(.background,in:RoundedRectangle(cornerRadius:20)).clipShape(RoundedRectangle(cornerRadius:20))
    }
}

struct DateRangeFields: View {
    @Binding var start: Date; @Binding var end: Date
    var body: some View {
        DatePicker("Check-in",selection:$start,in:Date()...,displayedComponents:.date)
        DatePicker("Check-out",selection:$end,in:start.addingDays(1)...,displayedComponents:.date)
            .onChange(of:start) { _,new in if end.dayCode <= new.dayCode { end = new.addingDays(1) } }
        Text("Nights include check-in and exclude check-out. Dates are local to the place.").font(.caption).foregroundStyle(.secondary)
    }
}

struct RoomDetailView: View {
    @EnvironmentObject var store: Store
    let roomId: String
    var initialStart = Date()
    var initialEnd = Date().addingDays(1)
    @State private var start = Date()
    @State private var end = Date().addingDays(1)
    @State private var guests = 1
    @State private var message = ""
    @State private var sent = false
    @State private var month = Date()
    var room: Room? { store.snapshot?.rooms.first { $0.id == roomId } }
    var body: some View {
        Group {
            if let r = room, let s = store.snapshot {
                List {
                    if !s.photos.filter({$0.roomId == r.id}).isEmpty {
                        Section {
                            TabView {
                                ForEach(s.photos.filter {$0.roomId == r.id}) { RoomPhoto(photoId:$0.id).frame(height:250).clipped() }
                            }.tabViewStyle(.page).frame(height:250).listRowInsets(EdgeInsets())
                        }
                    }
                    Section {
                        Text(r.title).font(.system(.title,design:.serif))
                        Label(r.location,systemImage:"mappin.and.ellipse")
                        Text("\(r.street) · \(r.postalCode)").foregroundStyle(.secondary)
                        Label("Hosted by \(r.hostName)",systemImage:"person.crop.circle")
                        Label("Up to \(r.guests) guests · \(r.roomType.capitalized)",systemImage:"bed.double")
                        if !r.description.isEmpty { Text(r.description) }
                        Text("Local time zone: \(r.timezone)").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Availability") {
                        MonthGrid(month:$month,selected:$start) { date in s.isFree(r,date.dayCode) ? 1 : 0 }
                        Text("Green = free · Plain = busy or not offered").font(.caption).foregroundStyle(.secondary)
                    }
                    if r.ownerId != store.userId {
                        Section("Request a stay") {
                            DateRangeFields(start:$start,end:$end)
                            Stepper("\(guests) guest\(guests == 1 ? "" : "s")",value:$guests,in:1...r.guests)
                            TextField("A note for your host",text:$message,axis:.vertical).lineLimit(3...6)
                            let free = s.isFree(r,start:start,end:end)
                            Label(free ? "Free for these nights" : "Choose dates shown as free",systemImage:free ? "checkmark.circle.fill" : "calendar.badge.exclamationmark").foregroundStyle(free ? forest : .secondary)
                            Button("Send stay request") {
                                Task { await store.run {
                                    try await store.mutate("stays",["room_id":r.id,"start":start.dayCode,"end":end.dayCode,"guests":guests,"message":message])
                                    sent = true
                                } }
                            }.disabled(!free || store.working || message.count > 2000)
                            Text("Your host needs to accept before the stay is confirmed. The exact meeting address can be arranged privately.").font(.caption).foregroundStyle(.secondary)
                        }
                    } else { Section { Text("Manage photos and dates in My places.").foregroundStyle(.secondary) } }
                }.navigationTitle(r.title).navigationBarTitleDisplayMode(.inline)
                    .alert("Request sent",isPresented:$sent) { Button("Lovely",role:.cancel) {} } message: { Text("You’ll find it in Stays. Your host can accept or decline it.") }
                    .onAppear { start = initialStart; end = initialEnd }
            } else { EmptyState(title:"Place unavailable",message:"The listing may have been removed.") }
        }
    }
}

struct MonthGrid: View {
    @Binding var month: Date
    @Binding var selected: Date
    let count: (Date) -> Int
    var calendar: Calendar { var c = Calendar.current; c.firstWeekday = 2; return c }
    var first: Date { calendar.date(from:calendar.dateComponents([.year,.month],from:month))! }
    var days: [Date?] {
        let offset = (calendar.component(.weekday,from:first)+5)%7
        return Array(repeating:nil,count:offset) + (calendar.range(of:.day,in:.month,for:first)!).map { first.addingDays($0-1) }
    }
    var body: some View {
        VStack(spacing:14) {
            HStack {
                Button { month = calendar.date(byAdding:.month,value:-1,to:month)! } label: { Image(systemName:"chevron.left") }.accessibilityLabel("Previous month")
                Spacer(); Text(month.formatted(.dateTime.month(.wide).year())).font(.headline); Spacer()
                Button { month = calendar.date(byAdding:.month,value:1,to:month)! } label: { Image(systemName:"chevron.right") }.accessibilityLabel("Next month")
            }.buttonStyle(.borderless)
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:4),count:7),spacing:8) {
                ForEach(["M","T","W","T","F","S","S"].indices,id:\.self) { i in Text(["M","T","W","T","F","S","S"][i]).font(.caption).foregroundStyle(.secondary) }
                ForEach(days.indices,id:\.self) { i in
                    if let day = days[i] {
                        let n = count(day)
                        Button { selected = day } label: {
                            VStack(spacing:3) { Text("\(calendar.component(.day,from:day))").font(.callout.weight(.medium)); Circle().fill(n > 0 ? forest : .clear).frame(width:4,height:4) }
                                .frame(maxWidth:.infinity,minHeight:40)
                                .foregroundStyle(day.dayCode == selected.dayCode ? .white : .primary)
                                .background(day.dayCode == selected.dayCode ? forest : n > 0 ? forest.opacity(0.12) : .clear,in:RoundedRectangle(cornerRadius:10))
                        }.buttonStyle(.plain).accessibilityLabel("\(day.formatted(date:.complete,time:.omitted)), \(n) free place\(n == 1 ? "" : "s")")
                    } else { Color.clear.frame(height:40) }
                }
            }
        }.padding(.vertical,6)
    }
}

struct NetworkCalendarView: View {
    @EnvironmentObject var store: Store
    @State private var month = Date()
    @State private var selected = Date()
    var networkRooms: [Room] { store.snapshot?.rooms.filter {$0.networkId == store.selectedNetwork} ?? [] }
    var free: [Room] { networkRooms.filter { store.snapshot?.isFree($0,selected.dayCode) == true } }
    var body: some View {
        NavigationStack {
            List {
                Section { NetworkPicker() }
                Section {
                    MonthGrid(month:$month,selected:$selected) { day in networkRooms.filter { store.snapshot?.isFree($0,day.dayCode) == true }.count }
                    Text("Green marks nights with a free place in your network. Tap a date to see where.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Free on \(selected.formatted(date:.abbreviated,time:.omitted))") {
                    if free.isEmpty { Text("No places offered for this night.").foregroundStyle(.secondary) }
                    ForEach(free) { r in NavigationLink { RoomDetailView(roomId:r.id,initialStart:selected,initialEnd:selected.addingDays(1)) } label: { VStack(alignment:.leading,spacing:5) { Text(r.title).font(.headline); Text("\(r.location) · \(r.hostName)").font(.subheadline).foregroundStyle(.secondary) } } }
                }
            }.navigationTitle("A world of welcome").refreshable { await store.refresh() }
        }
    }
}

struct HostingView: View {
    @EnvironmentObject var store: Store
    @State private var adding = false
    var body: some View {
        NavigationStack {
            List {
                Section { NetworkPicker(); Text("A spare room, a second guest room, the whole house or your van — each has its own calendar.").font(.subheadline).foregroundStyle(.secondary) }
                let rooms = store.snapshot?.rooms.filter { $0.ownerId == store.userId && $0.networkId == store.selectedNetwork } ?? []
                if rooms.isEmpty { EmptyState(title:"Make room for good company",message:"Add a place, upload a few photos and mark the nights you’d love to host.") }
                ForEach(rooms) { r in NavigationLink { ManageRoomView(roomId:r.id) } label: { VStack(alignment:.leading,spacing:6) { Text(r.title).font(.headline); Text(r.location).foregroundStyle(.secondary); Text("Manage photos & dates").font(.caption).foregroundStyle(forest) }.padding(.vertical,8) } }
                Section { Button { adding = true } label: { Label("Add a place",systemImage:"plus.circle.fill") }.disabled(store.network == nil) }
            }.navigationTitle("My places").sheet(isPresented:$adding) { RoomForm(networkId:store.selectedNetwork) }.refreshable { await store.refresh() }
        }
    }
}

struct RoomForm: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    let networkId: String
    var room: Room? = nil
    @State private var title = ""
    @State private var street = ""
    @State private var city = ""
    @State private var postal = ""
    @State private var country = ""
    @State private var description = ""
    @State private var timezone = TimeZone.current.identifier
    @State private var guests = 2
    @State private var type = "room"
    var valid: Bool { [title,street,city,postal,country].allSatisfy {!$0.trimmingCharacters(in:.whitespaces).isEmpty} }
    var body: some View {
        NavigationStack {
            Form {
                Section("Your place") {
                    TextField("A name for your place",text:$title)
                    Picker("Kind of place",selection:$type) { Text("Spare room").tag("room"); Text("Whole home").tag("home"); Text("Van / camper").tag("van") }
                    Stepper("Up to \(guests) guests",value:$guests,in:1...20)
                    TextField("What makes it a lovely place to stay?",text:$description,axis:.vertical).lineLimit(4...8)
                }
                Section("Where in the world?") {
                    TextField("Street name (no door number)",text:$street).textContentType(.streetAddressLine1)
                    TextField("Town / city",text:$city).textContentType(.addressCity)
                    TextField("Postcode / ZIP code",text:$postal).textContentType(.postalCode)
                    TextField("Country",text:$country).textContentType(.countryName)
                    Picker("Time zone",selection:$timezone) { ForEach(TimeZone.knownTimeZoneIdentifiers,id:\.self) { Text($0.replacingOccurrences(of:"_",with:" ")).tag($0) } }
                    Text("Share the street and postal code, without a house or flat number. For a van, use its current base. Arrange exact meeting details privately.").font(.caption).foregroundStyle(.secondary)
                }
                Section { Button(room == nil ? "Add this place" : "Save changes") {
                    dismissKeyboard()
                    Task { await store.run {
                        let body: [String:Any] = ["network_id":networkId,"title":title,"street":street,"city":city,"postal_code":postal,"country":country,"timezone":timezone,"description":description,"guests":guests,"room_type":type]
                        try await store.mutate(room.map {"rooms/\($0.id)"} ?? "rooms",method:room == nil ? "POST" : "PATCH",body)
                        dismiss()
                    } }
                }.disabled(!valid || store.working) }
            }.navigationTitle(room == nil ? "A place to share" : "Edit place").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } } }
                .onAppear { if let r = room { title=r.title; street=r.street; city=r.city; postal=r.postalCode; country=r.country; description=r.description; timezone=r.timezone; guests=r.guests; type=r.roomType } }
        }
    }
}

struct ManageRoomView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    let roomId: String
    @State private var edit = false
    @State private var dates = false
    @State private var deleteRoom = false
    @State private var deletePeriod: Period?
    @State private var deletePhoto: Photo?
    @State private var photo: PhotosPickerItem?
    @State private var uploading = false
    var room: Room? { store.snapshot?.rooms.first {$0.id == roomId} }
    var body: some View {
        Group {
            if let r = room {
                List {
                    Section { Text(r.location).foregroundStyle(.secondary); Button("Edit listing") { edit = true } }
                    Section("Photos (up to 8)") {
                        let photos = store.snapshot?.photos.filter {$0.roomId == roomId} ?? []
                        ForEach(photos) { p in
                            VStack(alignment:.trailing) {
                                RoomPhoto(photoId:p.id).frame(height:190).clipShape(RoundedRectangle(cornerRadius:12))
                                Button("Remove photo",role:.destructive) { deletePhoto = p }.font(.caption)
                            }
                        }
                        PhotosPicker(selection:$photo,matching:.images,photoLibrary:.shared()) { Label(uploading ? "Preparing photo…" : "Add a photo",systemImage:"photo.badge.plus") }.disabled(uploading || store.working || photos.count >= 8)
                        Text("Photos are visible only within this network. Location metadata is removed before upload.").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Free & busy dates") {
                        Button { dates = true } label: { Label("Add dates",systemImage:"calendar.badge.plus") }
                        let periods = store.snapshot?.periods.filter {$0.roomId == roomId}.sorted {$0.start < $1.start} ?? []
                        if periods.isEmpty { Text("No nights offered yet. Add free dates to welcome your network.").foregroundStyle(.secondary) }
                        ForEach(periods) { p in
                            HStack {
                                Image(systemName:p.kind == "free" ? "sun.max.fill" : "moon.fill").foregroundStyle(p.kind == "free" ? forest : .secondary)
                                VStack(alignment:.leading,spacing:4) { Text(p.kind == "free" ? "Free to stay" : "Busy").font(.headline); Text("\(dayLabel(p.start)) → \(dayLabel(p.end))").font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                Button(role:.destructive) { deletePeriod = p } label: { Image(systemName:"trash") }.buttonStyle(.borderless).accessibilityLabel("Remove \(p.kind) dates \(dayLabel(p.start)) to \(dayLabel(p.end))")
                            }
                        }
                        Text("Busy dates override free dates. Removing a busy block makes nights free again wherever a free period still covers them. Your network is notified when new nights become free.").font(.caption).foregroundStyle(.secondary)
                    }
                    Section { Button("Delete this place",role:.destructive) { deleteRoom = true } }
                }.navigationTitle(r.title).navigationBarTitleDisplayMode(.inline)
                    .sheet(isPresented:$edit) { RoomForm(networkId:r.networkId,room:r) }
                    .sheet(isPresented:$dates) { PeriodForm(room:r) }
                    .onChange(of:photo) { _,new in
                        guard let new else { return }
                        uploading = true
                        Task { @MainActor in
                            defer { uploading = false; photo = nil }
                            do {
                                guard let data = try await new.loadTransferable(type:Data.self), let image = UIImage(data:data) else { throw APIProblem(message:"Could not read this photo.") }
                                let scale = min(1,1400 / max(image.size.width,image.size.height))
                                let size = CGSize(width:image.size.width*scale,height:image.size.height*scale)
                                let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
                                let resized = UIGraphicsImageRenderer(size:size,format:format).image { ctx in
                                    UIColor.white.setFill(); ctx.fill(CGRect(origin:.zero,size:size)); image.draw(in:CGRect(origin:.zero,size:size))
                                }
                                guard let jpg = resized.jpegData(compressionQuality:0.72), jpg.count <= 1_000_000 else { throw APIProblem(message:"This photo is too large. Choose a smaller image.") }
                                await store.run { try await store.mutate("rooms/\(r.id)/photos",["image":jpg.base64EncodedString()]) }
                            } catch { store.error = error.localizedDescription }
                        }
                    }
                    .confirmationDialog("Delete this place, its photos, dates and stay requests?",isPresented:$deleteRoom,titleVisibility:.visible) { Button("Delete place",role:.destructive) { Task { await store.run { try await store.mutate("rooms/\(r.id)",method:"DELETE"); dismiss() } } } }
                    .confirmationDialog("Remove these dates?",isPresented:Binding(get:{deletePeriod != nil},set:{if !$0 {deletePeriod=nil}}),titleVisibility:.visible) {
                        if let p = deletePeriod { Button("Remove dates",role:.destructive) { Task { await store.run { try await store.mutate("periods/\(p.id)",method:"DELETE") }; deletePeriod=nil } } }
                    }
                    .confirmationDialog("Remove this photo?",isPresented:Binding(get:{deletePhoto != nil},set:{if !$0 {deletePhoto=nil}}),titleVisibility:.visible) {
                        if let p = deletePhoto { Button("Remove photo",role:.destructive) { Task { await store.run { try await store.mutate("photos/\(p.id)",method:"DELETE") }; deletePhoto=nil } } }
                    }
            } else { EmptyState(title:"Place removed",message:"This listing is no longer available.") }
        }
    }
}
struct PeriodForm: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    let room: Room
    @State private var start = Date()
    @State private var end = Date().addingDays(1)
    @State private var kind = "free"
    var body: some View {
        NavigationStack {
            Form {
                Section { Picker("These nights are",selection:$kind) { Text("Free").tag("free"); Text("Busy").tag("busy") }.pickerStyle(.segmented) }
                Section { DateRangeFields(start:$start,end:$end) }
                Section {
                    Text(kind == "free" ? "The network will be notified about nights that become newly available." : "Busy nights override free nights. Accepted stays must be cancelled first.").font(.subheadline).foregroundStyle(.secondary)
                    Button("Save dates") { Task { await store.run { try await store.mutate("rooms/\(room.id)/periods",["start":start.dayCode,"end":end.dayCode,"kind":kind]); dismiss() } } }.disabled(store.working || start.dayCode >= end.dayCode)
                }
            }.navigationTitle("Make room in the diary").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

struct StaysView: View {
    @EnvironmentObject var store: Store
    @State private var segment = "guest"
    var body: some View {
        NavigationStack {
            List {
                Section { NetworkPicker(); Picker("Stays",selection:$segment) { Text("My trips").tag("guest"); Text("Hosting").tag("host") }.pickerStyle(.segmented) }
                let stays = store.snapshot?.stays.filter { $0.networkId == store.selectedNetwork && (segment == "guest" ? $0.guestId == store.userId : $0.hostId == store.userId) } ?? []
                if stays.isEmpty { EmptyState(title:segment == "guest" ? "Your next visit starts here" : "Good company is on its way",message:segment == "guest" ? "Find a place in Explore and request your dates." : "Stay requests for your places will appear here.",icon:"suitcase") }
                ForEach(stays) { StayRow(stay:$0) }
            }.navigationTitle("Visits to look forward to").refreshable { await store.refresh() }
        }
    }
}
struct StayRow: View {
    @EnvironmentObject var store: Store
    let stay: Stay
    @State private var cancel = false
    var body: some View {
        Section {
            VStack(alignment:.leading,spacing:10) {
                HStack(alignment:.top) { Text(stay.roomTitle).font(.headline); Spacer(); Text(stay.status.capitalized).font(.caption.weight(.semibold)).padding(.horizontal,10).padding(.vertical,5).background((stay.status == "accepted" ? forest : .gray).opacity(0.12),in:Capsule()) }
                Text("\(dayLabel(stay.start)) → \(dayLabel(stay.end))")
                Text("\(stay.guestName) · \(stay.guests) guest\(stay.guests == 1 ? "" : "s")").font(.subheadline).foregroundStyle(.secondary)
                if !stay.message.isEmpty { Text(stay.message).font(.subheadline).padding(12).frame(maxWidth:.infinity,alignment:.leading).background(sand,in:RoundedRectangle(cornerRadius:10)) }
                if stay.status == "pending" && stay.hostId == store.userId {
                    HStack { Button("Accept") { update("accepted") }.buttonStyle(.borderedProminent); Button("Decline",role:.destructive) { update("declined") }.buttonStyle(.bordered) }.disabled(store.working)
                }
                if stay.status == "pending" || stay.status == "accepted" { Button("Cancel \(stay.status == "pending" ? "request" : "stay")",role:.destructive) { cancel = true }.font(.subheadline).disabled(store.working) }
                if stay.status == "accepted" { Text("Confirmed. Arrange your arrival and exact address privately with your host.").font(.caption).foregroundStyle(forest) }
            }.padding(.vertical,6)
        }.confirmationDialog("Cancel this stay? Both host and guest will see the update.",isPresented:$cancel,titleVisibility:.visible) { Button("Cancel stay",role:.destructive) { update("cancelled") } }
    }
    func update(_ status: String) { Task { await store.run { try await store.mutate("stays/\(stay.id)",["status":status]) } } }
}

struct NetworksView: View {
    @EnvironmentObject var store: Store
    @State private var name = ""
    @State private var code = ""
    @State private var settings = false
    @State private var destructive = ""
    @State private var target: Member?
    var body: some View {
        NavigationStack {
            List {
                if let n = store.network {
                    Section {
                        NetworkPicker()
                        Text(n.code).font(.system(.largeTitle,design:.monospaced).weight(.medium)).textSelection(.enabled).frame(maxWidth:.infinity).padding(.vertical,12)
                        ShareLink(item:"Join \(n.name) on Spare Room. Network code: \(n.code)\nhttps://rooms.leobrown.co.uk") { Label("Share network code",systemImage:"square.and.arrow.up") }
                        Text("Anyone with this code can join and see the network’s listings. Share it with people you trust.").font(.caption).foregroundStyle(.secondary)
                        Toggle("Notify me about this network",isOn:Binding(get:{n.muted == 0},set:{ value in Task { await store.run { try await store.mutate("networks/\(n.id)/mute",["muted":!value]) } } })).disabled(store.working)
                    } header: { Text(n.name) }
                    Section("Your people") {
                        ForEach(store.snapshot?.members.filter {$0.networkId == n.id} ?? []) { m in
                            HStack { Label(m.name,systemImage:"person.crop.circle"); Spacer(); if m.id == n.ownerId { Text("Owner").font(.caption).foregroundStyle(.secondary) }
                                if n.ownerId == store.userId && m.id != store.userId { Button(role:.destructive) { target = m } label: { Image(systemName:"person.crop.circle.badge.minus") }.buttonStyle(.borderless).accessibilityLabel("Remove \(m.name)") }
                            }
                        }
                    }
                    Section {
                        if n.ownerId == store.userId {
                            Button("Generate a new joining code") { destructive = "rotate" }
                            Button("Delete network",role:.destructive) { destructive = "delete" }
                        } else { Button("Leave network",role:.destructive) { destructive = "leave" } }
                    }
                }
                Section("Create a network") {
                    TextField("Family, friends, chosen family…",text:$name)
                    Button("Create & get a code") { dismissKeyboard(); Task { await store.run {
                        let data = try await store.call("networks",method:"POST",body:["name":name])
                        if let value = try JSONSerialization.jsonObject(with:data) as? [String:Any], let id = value["id"] as? String { store.selectedNetwork=id }; name=""
                    } } }.disabled(store.working || name.trimmingCharacters(in:.whitespaces).isEmpty)
                }
                Section("Join a network") {
                    TextField("Enter shared code",text:$code).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    Button("Join your people") { dismissKeyboard(); Task { await store.run {
                        let data = try await store.call("networks/join",method:"POST",body:["code":code])
                        if let value = try JSONSerialization.jsonObject(with:data) as? [String:Any], let id = value["id"] as? String { store.selectedNetwork=id }; code=""
                    } } }.disabled(store.working || code.trimmingCharacters(in:.whitespaces).isEmpty)
                }
                if !store.events.isEmpty {
                    Section("Recent updates") { ForEach(store.events.prefix(20)) { e in VStack(alignment:.leading,spacing:4) { Text(e.title).font(.headline); Text(e.body).font(.subheadline).foregroundStyle(.secondary) } } }
                }
            }.navigationTitle("Your networks").toolbar { ToolbarItem(placement:.topBarTrailing) { Button { settings=true } label: { Image(systemName:"gearshape") }.accessibilityLabel("Settings") } }
                .sheet(isPresented:$settings) { SettingsView() }
                .confirmationDialog(destructive == "rotate" ? "Replace the shared code? The old code will stop working. Existing members stay." : destructive == "delete" ? "Delete the network and all its places, photos and stays?" : "Leave this network? Your listings and stay requests in it will be removed.",isPresented:Binding(get:{!destructive.isEmpty},set:{if !$0 {destructive=""}}),titleVisibility:.visible) {
                    if let n=store.network {
                        let action=destructive
                        Button(action == "rotate" ? "Replace code" : action == "delete" ? "Delete network" : "Leave network",role:action == "rotate" ? nil : .destructive) { Task { await store.run { try await store.mutate(action == "delete" ? "networks/\(n.id)" : "networks/\(n.id)/\(action)",method:action == "delete" ? "DELETE" : "POST") }; destructive="" } }
                    }
                }
                .confirmationDialog("Remove this person and their listings and requests from the network?",isPresented:Binding(get:{target != nil},set:{if !$0 {target=nil}}),titleVisibility:.visible) {
                    if let m=target { Button("Remove \(m.name)",role:.destructive) { Task { await store.run { try await store.mutate("networks/\(m.networkId)/members/\(m.id)",method:"DELETE") }; target=nil } } }
                }
                .refreshable { await store.refresh() }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State private var showRecovery = false
    @State private var delete = false
    @State private var password = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Your account") {
                    Text(store.snapshot?.user.name ?? "")
                    Text(store.snapshot?.user.email ?? "").foregroundStyle(.secondary)
                    if let key=store.recoveryKey {
                        Toggle("Show recovery key",isOn:$showRecovery)
                        if showRecovery { Text(key).font(.system(.body,design:.monospaced)).textSelection(.enabled); ShareLink(item:key) { Label("Save recovery key",systemImage:"square.and.arrow.up") } }
                    }
                    Text("Keep your recovery key somewhere private. It lets you reset a forgotten password; there is no email reset service.").font(.caption).foregroundStyle(.secondary)
                }
                Section("iPhone notifications") {
                    Toggle("Availability & stay updates",isOn:Binding(get:{store.notifications},set:{ value in if value { Task { await store.enableNotifications() } } else { store.disableNotifications() } }))
                    Text("Your iPhone periodically checks for new free dates and stay updates. iOS controls timing, so notifications may be delayed. Background App Refresh must be enabled; force-quitting the app stops background checks until you reopen it.").font(.caption).foregroundStyle(.secondary)
                    Button("Open iPhone settings") { if let url=URL(string:UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                }
                Section("Open source") {
                    Link("Source code on GitHub",destination:URL(string:"https://github.com/leo-brown/spare-room")!)
                    Link("Privacy",destination:URL(string:"https://rooms.leobrown.co.uk/privacy")!)
                    Text("Spare Room 1.0 · Made for your people").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Button("Sign out") { Task { await store.logout(); if !store.signedIn {dismiss()} } }.disabled(store.working)
                    Button("Delete account",role:.destructive) { delete=true }
                }
                if delete {
                    Section("Permanently delete your account") {
                        Text("This removes your profile, photos, listings and stays. If you own a network with other members, delete that network first.").font(.subheadline)
                        SecureField("Confirm your password",text:$password)
                        Button("Permanently delete",role:.destructive) { Task { await store.run(refresh:false) { try await store.mutate("account",method:"DELETE",["password":password]); store.clearSession(); dismiss() } } }.disabled(password.count < 10 || store.working)
                    }
                }
            }.navigationTitle("Make yourself at home").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
