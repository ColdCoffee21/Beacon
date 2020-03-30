import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';


import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  //Google maps variables
  GoogleMapController mapController;
  Geolocator geoLocator = Geolocator();
  StreamSubscription<Position> _positionStream;
  Map<String, Circle> mCircles = <String, Circle>{};

  //Shared preferences
  SharedPreferences prefs;
  //Fire-store variable
  Firestore fireStore = Firestore.instance;

  bool _beaconActive = false;
  bool _create = false;
  bool beaconCancel = false;
  bool folBeacon = false;
  bool folBeaconCancel = false;
  bool unSubF = false;

  var sSub;
  String ownBeaconName;
  BitmapDescriptor beaconIcon;

  var _scaffoldKey = new GlobalKey<ScaffoldState>();

  LatLng _center = LatLng(12.979406, 80.220879);

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  void loadBeaconPin() async {
    beaconIcon = await BitmapDescriptor.fromAssetImage(
        ImageConfiguration(devicePixelRatio: 2.5),
        'assets/beaconMarker.png');
  }

  initUserLoc() async{
    Position curLoc = await geoLocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best);
    _center = LatLng(curLoc.latitude, curLoc.longitude);
  }

  setUpSF() async {
    prefs = await SharedPreferences.getInstance();
  }

  @override
  void initState(){
    super.initState();
    loadBeaconPin();
    setUpSF();
    initUserLoc();
    _positionStream = geoLocator
        .getPositionStream(LocationOptions(
        accuracy: LocationAccuracy.best, timeInterval: 1000))
        .listen((position) async {
          mapController?.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: LatLng(
                  position.latitude,
                  position.longitude,
                ),
                zoom: 14.0,
              ),
            ),
          );
          if(folBeacon && mCircles.containsKey("fLocation") && mCircles.containsKey("curLocation")){
            mapController?.animateCamera(
              CameraUpdate.newLatLngBounds(setBounds(), 100)
              );
          }
          if(_beaconActive && _create)
            {
              try {
                print("UPDATE LAT ${position.latitude} LONG ${position.longitude}");
                fireStore
                    .collection('Beacons')
                    .document(ownBeaconName)
                    .updateData({'latitude': position.latitude, 'longitude': position.longitude});
              } catch (e) {
                print(e.toString());
              }
            }
          this.setState(() {
            mCircles["curLocation"] = Circle(
                circleId: CircleId("curLocation"),
                radius: position.accuracy,
                zIndex: 1,
                strokeColor: Colors.blue,
                center: LatLng(position.latitude, position.longitude),
                fillColor: Colors.blue.withAlpha(70));
          });
    });
  }

  void createBeacon(String name) async {
    print("CREATE $name");
    Position curLoc = await geoLocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best);
    print("CREATE LAT ${curLoc.latitude} LONG ${curLoc.longitude}");
    await fireStore.collection("Beacons")
        .document("$name")
        .setData({
      'latitude': curLoc.latitude,
      'longitude': curLoc.longitude,
    });
    _create = true;
    prefs.setBool('beaconActive', true);
    prefs.setString("beaconName", name);
    //delete record after 3 hours
    Timer(Duration(hours: 3), () {
      stopBeacon();
      _beaconActive = false;
    });
  }

  void stopBeacon() async
  {
    try {
      _create = false;
      await fireStore
          .collection('Beacons')
          .document(prefs.getString('beaconName'))
          .delete();
      prefs.setBool('beaconActive', false);
      prefs.remove("beaconName");
    } catch (e) {
      print(e.toString());
    }

  }

  bool checkActive() {
    if(prefs.containsKey('beaconActive')) {
      return prefs.getBool('beaconActive');
    }
    else{
      return false;
    }
  }
  Future<String> beBeacon(BuildContext context)
  {
    TextEditingController passkeyController =  TextEditingController();
    return showDialog(context: context, builder: (context){
      return SimpleDialog(
        title: Text("Be the beacon",
          textAlign: TextAlign.center,),
          titlePadding: EdgeInsets.fromLTRB(30.0, 20.0, 30.0, 5.0),
        children: checkActive() ? cancelBeacon(context) : <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(20.0, 0.0, 20.0, 2.0),
            //EdgeInsets.all(20.0),
            child: Text("Your location will be shared until beacon is stopped. Beacon battery lasts for 3 hours."),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20.0, 0.0, 20.0, 5.0),
            //EdgeInsets.all(20.0),
            child: TextField(
              controller: passkeyController,
              cursorColor: Colors.amber,
              keyboardType: TextInputType.text,
              decoration: InputDecoration(
                hintText: 'Enter your passkey',
              ),
            ),
          ),
          MaterialButton(
            elevation: 5.0,
            child: Text("Submit"),
            onPressed: () {
              String pKey = passkeyController.text.toString();
              if(pKey.length>0) {
                _beaconActive = true;
                beaconCancel = false;
                Navigator.of(context).pop(pKey);
              }
              else {
                _beaconActive = false;
                beaconCancel = true;
                Navigator.of(context).pop();
              }
            },
          ),
          MaterialButton(
            elevation: 5.0,
            child: Text("Cancel"),
            onPressed: () {
              _beaconActive = false;
              beaconCancel = true;
              Navigator.of(context).pop();
            },
          ),
        ],
        elevation: 4,
      );
    });
  }

  List<Widget> cancelBeacon(BuildContext context) {
    return [
      Padding(
        padding: EdgeInsets.fromLTRB(20.0, 0.0, 20.0, 5.0),
        //EdgeInsets.all(20.0),
        child: Text("Your Beacon is already active."),
      ),
      MaterialButton(
        elevation: 5.0,
        child: Text("Stop Beacon"),
        onPressed: () {
          stopBeacon();
          _beaconActive = false;
          beaconCancel = true;
          Navigator.of(context).pop();
        },
      ),
      MaterialButton(
        elevation: 5.0,
        child: Text("Cancel"),
        onPressed: () {
          beaconCancel = true;
          Navigator.of(context).pop();
        },
      ),
    ];
  }

  Future<String> followBeacon(BuildContext context)
  {
    TextEditingController passkeyController =  TextEditingController();
    return showDialog(context: context, builder: (context){
      return SimpleDialog(
        title: Text("Follow the beacon",
          textAlign: TextAlign.center,),
        titlePadding: EdgeInsets.fromLTRB(30.0, 20.0, 30.0, 5.0),
        children: folBeacon? cancelFollow(context) : <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(20.0, 0.0, 20.0, 5.0),
            //EdgeInsets.all(20.0),
            child: TextField(
              controller: passkeyController,
              cursorColor: Colors.amber,
              keyboardType: TextInputType.text,
              decoration: InputDecoration(
                hintText: 'Enter passkey of beacon',
              ),
            ),
          ),
          MaterialButton(
            elevation: 5.0,
            child: Text("Submit"),
            onPressed: () {
              String pKey = passkeyController.text.toString();
              if(pKey.length>0) {
                folBeacon = true;
                folBeaconCancel = false;
                Navigator.of(context).pop(pKey);
              }
              else {
                folBeacon = false;
                folBeaconCancel = true;
                mCircles.remove("fLocation");
                Navigator.of(context).pop();
              }
            },
          ),
          MaterialButton(
          elevation: 5.0,
          child: Text("Cancel"),
          onPressed: () {
            folBeaconCancel = true;
            Navigator.of(context).pop();
          },),
        ],
        elevation: 4,
      );
    });
  }

  List<Widget> cancelFollow(BuildContext context) {
    return [
      Padding(
        padding: EdgeInsets.fromLTRB(20.0, 0.0, 20.0, 5.0),
        //EdgeInsets.all(20.0),
        child: Text("You are already following a beacon."),
      ),
      MaterialButton(
        elevation: 5.0,
        child: Text("Unfollow Beacon"),
        onPressed: () {
          sSub.cancel();
          folBeacon = false;
          folBeaconCancel = true;
          this.setState(() {
            mCircles.remove("fLocation");
          });
          Navigator.of(context).pop();
        },
      ),
      MaterialButton(
        elevation: 5.0,
        child: Text("Cancel"),
        onPressed: () {
          folBeaconCancel = true;
          Navigator.of(context).pop();
        },
      ),
    ];
  }
  LatLngBounds boundsFromLatLngList(List<LatLng> list) {
    double x0, x1, y0, y1;
    for (LatLng latLng in list) {
      if (x0 == null) {
        x0 = x1 = latLng.latitude;
        y0 = y1 = latLng.longitude;
      } else {
        if (latLng.latitude > x1) x1 = latLng.latitude;
        if (latLng.latitude < x0) x0 = latLng.latitude;
        if (latLng.longitude > y1) y1 = latLng.longitude;
        if (latLng.longitude < y0) y0 = latLng.longitude;
      }
    }
    return LatLngBounds(northeast: LatLng(x1, y1), southwest: LatLng(x0, y0));
  }
  setBounds() {
    List<LatLng> locations = <LatLng>[];
    for(Circle v in mCircles.values){
      locations.add(v.center);
    }
    return boundsFromLatLngList(locations);
  }

  following(String pKey) {
    var docRef = fireStore.collection("Beacons").document(pKey);
    sSub = docRef.snapshots().listen((event) {
      var posDet = event.data;
      if(posDet == null){
        unSubscribeFollow();
        return;
      }
      double lat = posDet["latitude"];
      double long = posDet["longitude"];
      LatLng point = LatLng(lat, long);
      this.setState(() {
        mCircles["fLocation"] = Circle(
            radius: 25.0,
            circleId: CircleId("fLocation"),
            zIndex: 1,
            strokeColor: Colors.red,
            center: point,
            fillColor: Colors.red.withAlpha(70));
        setBounds();
      });
    });
  }

  unSubscribeFollow(){
    sSub.cancel();
    folBeacon = false;
    SnackBar shutDown = SnackBar(content: Text("Beacon was shut down"),);
    _scaffoldKey.currentState.showSnackBar(shutDown);
    this.setState(() {
      mCircles.remove("fLocation");
    });
  }

  Widget button(Function function, IconData icon) {
    return FloatingActionButton(
      onPressed: function,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      backgroundColor: Colors.green,
      child: Icon(
        icon,
        size: 36.0,
      ),
    );
  }
  Set<Circle> checkCircle(){
    if(mCircles.isEmpty){
      return Set<Circle>.of([]);
    }
    else{
      return Set<Circle>.of([mCircles["curLocation"]]);
    }
  }
  Set<Marker> checkMarker() {
    if(!folBeacon || !(mCircles.containsKey("fLocation"))){
      return Set<Marker>.of([]);
    }
    else{
      return Set<Marker>.of([Marker(
        markerId: MarkerId("fMarker"),
        position: LatLng(mCircles["fLocation"].center.latitude,mCircles["fLocation"].center.longitude),
        draggable: false,
        icon: beaconIcon,
        zIndex: 1,
        flat: true,)]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          title: Text('Beacon'),
          backgroundColor: Colors.green[700],
          centerTitle: true,
        ),
        body: Builder(builder: (context) => Stack(
          children: <Widget>[
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _center,
                zoom: 11.0,
              ),
              myLocationEnabled: true,
              markers: checkMarker(),
              circles: checkCircle(),
              onMapCreated: _onMapCreated,
            ),
            Padding(
              padding: EdgeInsets.all(16.0),
              child: Align(
                alignment: Alignment.topLeft,
                child: Column(
                  children: <Widget>[
                    button(() {
                      return followBeacon(context).then((onValue){
                        if(!folBeaconCancel) {
                          fireStore.collection("Beacons").document("$onValue").get().then((doc) {
                            if (doc.exists) {
                              SnackBar trial = SnackBar(content: Text("Following Passkey: $onValue"),);
                              Scaffold.of(context).showSnackBar(trial);
                              following(onValue);
                            }
                            else {
                              folBeacon = false;
                              SnackBar trial = SnackBar(content: Text("Passkey does not exist!"),);
                              Scaffold.of(context).showSnackBar(trial);
                            }
                          });
                        }
                      }
                      );}, Icons.wifi_tethering),
                    SizedBox(
                      height: 16.0,
                    ),
                    button( () {
                      return beBeacon(context).then((onValue){
                        if(!beaconCancel) {
                          fireStore.collection("Beacons").document("$onValue").get().then((doc) {
                            if (doc.exists) {
                              _beaconActive = false;
                              SnackBar trial = SnackBar(content: Text("Passkey already exists! Try another."),);
                              Scaffold.of(context).showSnackBar(trial);
                            }
                            else {
                              SnackBar trial = SnackBar(content: Text("Generated Passkey: $onValue "),);
                              Scaffold.of(context).showSnackBar(trial);
                              ownBeaconName = onValue;
                              if(_beaconActive)
                                createBeacon(ownBeaconName);
                            }
                          });

                        }
                      }
                      );}, Icons.location_on), //button
                  ],
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
  @override
  void dispose() {
    if (_positionStream != null) {
      _positionStream.cancel();
    }
    stopBeacon();
    super.dispose();
  }
}