var TYPE_MIX  = 0;# plan has both mission and RTB
var TYPE_RTB  = 1;# return to base plan
var TYPE_MISS = 2;# mission plan
var TYPE_AREA = 3;# map area (LV)

var COLOR_GREY_LIGHT = [0.70,0.70,0.70];

var TRUE  = 1;
var FALSE = 0;

var maxLV = 8;
var maxSteers = 48;

var debugAll = FALSE;

var printDA = func (str) {
    if (debugAll) print (str);
}

var Polygon = {
	#
	# Class methods and variables
	#
	primary: nil,#its used in routemanager
	editing: nil,#its set for being edited
	editRTB: nil,
	editMiss: nil,
	polys: {},
	_activating: FALSE,
	flyRTB: nil,
	flyMiss: nil,
	editSteer: FALSE,  # selectSteer set for being moved
	appendSteer: FALSE,# set for append
	insertSteer: FALSE,# selectSteer set for having something inserted
	selectSteer: nil,# content: [leg ghost, index]
	selectL: nil,# when selectSteer is non nil, this will be listener for route-manager edit of plan. Such edit will cancel all editing. Hackish.
	editDetail: FALSE,# selectSteer ready for having an attribute edited
	_apply: FALSE,
	jumpToSteer: nil,
	editBullsEye: FALSE,
	#polyEdit: FALSE,

	setupJAPolygons: func {
		Polygon._setupListeners();
		me.multi = getprop("ja37/supported/multiple-flightplans");
		if (me.multi == TRUE) {
			var poly1 = Polygon.new("1", "", TYPE_MISS, getprop("xmlPlans/mission1"), FALSE);
			Polygon.polys["1"] = poly1;
			for (var i = 2; i<=4; i+=1) {
				var poly = Polygon.new(""~i, "", TYPE_MISS, getprop("xmlPlans/mission"~i));
				Polygon.polys[""~i] = poly;
			}
			for (var i = 1; i<=1; i+=1) {#TODO: there should be 4, but until JA nav. panel is modeled, making only 1
				var polyA = Polygon.new(""~i, "A", TYPE_RTB, getprop("xmlPlans/rtb"~i~"A"));
				Polygon.polys[polyA.getName()]   = polyA;

				var polyB = Polygon.new(""~i, "B", TYPE_RTB, getprop("xmlPlans/rtb"~i~"B"));
				Polygon.polys[polyB.getName()]   = polyB;
			}
			for (var i = 1; i<=6; i+=1) {
				var poly = Polygon.new("OP"~i, "", TYPE_AREA, getprop("xmlPlans/area"~i));
				Polygon.polys["OP"~i] = poly;
			}
		
			Polygon.editRTB      = polyA;
			Polygon.editMiss     = poly1;
			Polygon.flyRTB       = polyA;
			Polygon.flyMiss      = poly1;
			poly1.setAsPrimary();
		} else {
			var poly1 = Polygon.new("1", "", TYPE_MIX, nil, TRUE);
			Polygon.primary      = poly1;
			Polygon.flyRTB       = poly1;
			Polygon.flyMiss      = poly1;
			Polygon.editRTB      = poly1;
			Polygon.editMiss     = poly1;
		}
		printDA("JA: finished plan Init");
	},

	setupAJPolygons: func {
		Polygon._setupListeners();
		var poly1 = Polygon.new("1", "", TYPE_MIX, nil, TRUE);
		Polygon.primary      = poly1;
		Polygon.flyRTB       = poly1;
		Polygon.flyMiss      = poly1;
		Polygon.editRTB      = poly1;
		Polygon.editMiss     = poly1;
		printDA("AJ: finished plan Init");
	},

	saveAll: func {
		#dont use, is only for testing
		var key = keys(Polygon.polys);
		foreach (k; key) {
			var poly = Polygon.polys[k];
			poly.plan.save("C:/Users/Nikolai/AppData/Roaming/flightgear.org/Export/Viggen-autosave-"~poly.name);
		}
	},

	deletePlan: func {
		# Called from dap.
		if (Polygon.editing != nil) {
			printDA("deleting plan");
			Polygon.selectSteer = nil;
			Polygon.appendSteer = FALSE;
			Polygon.insertSteer = FALSE;
			Polygon.editSteer   = FALSE;
			Polygon.editDetail  = FALSE;
			Polygon.editing.plan = createFlightplan();
			Polygon.editing.plan.id = Polygon.editing.getName();
			if(Polygon.editing.isPrimary()) {
				Polygon._activating = TRUE;
				Polygon.editing.plan.activate();
				Polygon._activating = FALSE;
			}
			#Polygon.polyEdit = FALSE;
			#dap.set237(FALSE);
		}
	},

	selectSteerpoint: func (planName, leg, index) {
		#me.editIndex = Polygon.editing.plan.indexOfWP(leg); TODO: in 2 years time from now, start using this, as noone will be using old FG 2017.2.1 anymore.
		#printf("%s %s %d",planName, leg.id, me.editIndex);
		if (planName == Polygon.editing.getName()) {#} and me.editIndex != nil and me.editIndex != -1) {
			Polygon.selectSteer = [leg, index];
			printDA("select");
			if (me.selectL != nil) {
				removelistener(me.selectL);
			}
			me.selectL = setlistener("autopilot/route-manager/signals/edited", func {Polygon._planEdited()});
		}
	},

	jumpTo: func (leg, index) {
		Polygon.jumpToSteer = [leg, index];
	},
	
	jumpExecute: func {
		if (Polygon.jumpToSteer != nil) {
			if (Polygon.primary != nil and Polygon.primary.getSize() > Polygon.jumpToSteer[1]) {
				Polygon.primary.plan.current = Polygon.jumpToSteer[1];
			} else {
				print("error in jump");
			}
			Polygon.jumpToSteer = nil;
		}
	},

	editSteerpoint: func () {
		if (Polygon.selectSteer != nil) {
			Polygon.editDetail = FALSE;
			Polygon.appendSteer = FALSE;
			Polygon.insertSteer = FALSE;
			Polygon.editSteer = !Polygon.editSteer;
			printDA("toggle edit: "~Polygon.editSteer);
		}
		return Polygon.editSteer;
	},

	editApply: func (lati, long) {
		if (Polygon.editSteer) {
			Polygon._apply = TRUE;
			# TODO: what about name??!
			me.tempSpeed  = Polygon.selectSteer[0].speed_cstr;
			me.tempSpeedT = Polygon.selectSteer[0].speed_cstr_type;
			me.tempAlt    = Polygon.selectSteer[0].alt_cstr;
			me.tempAltT   = Polygon.selectSteer[0].alt_cstr_type;
			me.newName = sprintf("%s%d", Polygon.editing.getName(), (Polygon.selectSteer[1]+rand())*100);
			me.newSteerpoint = createWP({lat:lati,lon:long},me.newName,"pseudo");
			if (Polygon.selectSteer[1] == 0 and Polygon.editing.plan.departure != nil) {
				Polygon.editing.plan.departure = nil;
				#TODO:check if this also sets runway to nil.
				#printDA("edit dep runway is nil:"~(Polygon.editing.plan.departure_runway == nil));
			} elsif (Polygon.selectSteer[1] == Polygon.editing.getSize()-1 and Polygon.editing.plan.destination != nil) {
				Polygon.editing.plan.destination = nil;
				#TODO:check if this also sets runway to nil.
				#printDA("edit dest runway is nil:"~(Polygon.editing.plan.destination_runway == nil));
			} else {
				Polygon.editing.plan.deleteWP(Polygon.selectSteer[1]);
			}
			Polygon.editing.plan.insertWP(me.newSteerpoint, Polygon.selectSteer[1]);
			Polygon.selectSteer = [Polygon.editing.plan.getWP(Polygon.selectSteer[1]), Polygon.selectSteer[1]];
			if (me.tempAlt != nil and me.tempAltT != nil) {
				Polygon.selectSteer[0].setAltitude(me.tempAlt, me.tempAltT);
			}
			if (me.tempSpeed != nil and me.tempSpeedT != nil) {
				Polygon.selectSteer[0].setSpeed(me.tempSpeed,me.tempSpeedT);
			}
			Polygon._apply = FALSE;
		}
	},

	editDetailMethod: func (value) {
		if (Polygon.selectSteer != nil) {
			Polygon.editDetail  = value;
			Polygon.appendSteer = FALSE;
			Polygon.insertSteer = FALSE;
			Polygon.editSteer   = FALSE;
		} else {
			Polygon.editDetail = FALSE;
		}
	},

	setType: func (value) {
		if (Polygon.selectSteer != nil) {
#			Polygon.selectSteer[0].fly_type = value==1?"Target":Polygon.selectSteer[0].fly_type=="Target"?"flyOver":Polygon.selectSteer[0].fly_type;
		}
	},

	setLon: func (long) {
		if (Polygon.selectSteer != nil and Polygon.editDetail) {
			Polygon._apply = TRUE;
			# TODO: what about name??!
			me.newName    = sprintf("%s%d", Polygon.editing.getName(), (Polygon.selectSteer[1]+rand())*100);
			me.tempSpeed  = Polygon.selectSteer[0].speed_cstr;
			me.tempSpeedT = Polygon.selectSteer[0].speed_cstr_type;
			me.tempAlt    = Polygon.selectSteer[0].alt_cstr;
			me.tempAltT   = Polygon.selectSteer[0].alt_cstr_type;
			me.newSteerpoint = createWP({lat:Polygon.selectSteer[0].wp_lat,lon:long},me.newName,"pseudo");
			if (Polygon.selectSteer[1] == 0 and Polygon.editing.plan.departure != nil) {
				Polygon.editing.plan.departure = nil;
			} elsif (Polygon.selectSteer[1] == Polygon.editing.getSize()-1 and Polygon.editing.plan.destination != nil) {
				Polygon.editing.plan.destination = nil;
			} else {
				Polygon.editing.plan.deleteWP(Polygon.selectSteer[1]);
			}
			Polygon.editing.plan.insertWP(me.newSteerpoint, Polygon.selectSteer[1]);
			Polygon.selectSteer = [Polygon.editing.plan.getWP(Polygon.selectSteer[1]), Polygon.selectSteer[1]];
			#Polygon.selectSteer[0].speed_cstr      = me.tempSpeed;
			#Polygon.selectSteer[0].speed_cstr_type = me.tempSpeedT;
			#Polygon.selectSteer[0].alt_cstr        = me.tempAlt;
			#Polygon.selectSteer[0].alt_cstr_type   = me.tempAltT;
			if (me.tempAlt != nil and me.tempAltT != nil) {
				Polygon.selectSteer[0].setAltitude(me.tempAlt, me.tempAltT);
			}
			if (me.tempSpeed != nil and me.tempSpeedT != nil) {
				Polygon.selectSteer[0].setSpeed(me.tempSpeed,me.tempSpeedT);
			}
			Polygon._apply = FALSE;
		}
	},

	setLat: func (lati) {
		if (Polygon.selectSteer != nil and Polygon.editDetail) {
			Polygon._apply = TRUE;
			# TODO: what about name??!
			me.newName    = sprintf("%s%d", Polygon.editing.getName(), (Polygon.selectSteer[1]+rand())*100);
			me.tempSpeed  = Polygon.selectSteer[0].speed_cstr;
			me.tempSpeedT = Polygon.selectSteer[0].speed_cstr_type;
			me.tempAlt    = Polygon.selectSteer[0].alt_cstr;
			me.tempAltT   = Polygon.selectSteer[0].alt_cstr_type;
			me.newSteerpoint = createWP({lat:lati,lon:Polygon.selectSteer[0].wp_lon},me.newName,"pseudo");
			if (Polygon.selectSteer[1] == 0 and Polygon.editing.plan.departure != nil) {
				Polygon.editing.plan.departure = nil;
			} elsif (Polygon.selectSteer[1] == Polygon.editing.getSize()-1 and Polygon.editing.plan.destination != nil) {
				Polygon.editing.plan.destination = nil;
			} else {
				Polygon.editing.plan.deleteWP(Polygon.selectSteer[1]);
			}
			Polygon.editing.plan.insertWP(me.newSteerpoint, Polygon.selectSteer[1]);
			Polygon.selectSteer = [Polygon.editing.plan.getWP(Polygon.selectSteer[1]), Polygon.selectSteer[1]];
			#Polygon.selectSteer[0].speed_cstr      = me.tempSpeed;
			#Polygon.selectSteer[0].speed_cstr_type = me.tempSpeedT;
			#Polygon.selectSteer[0].alt_cstr        = me.tempAlt;
			#Polygon.selectSteer[0].alt_cstr_type   = me.tempAltT;
			if (me.tempAlt != nil and me.tempAltT != nil) {
				Polygon.selectSteer[0].setAltitude(me.tempAlt, me.tempAltT);
			}
			if (me.tempSpeed != nil and me.tempSpeedT != nil) {
				Polygon.selectSteer[0].setSpeed(me.tempSpeed,me.tempSpeedT);
			}
			Polygon._apply = FALSE;
		}
	},

	setMach: func (mach) {
		if (Polygon.selectSteer != nil and Polygon.editDetail) {
			#Polygon.selectSteer[0].speed_cstr_type = "mach";
			#Polygon.selectSteer[0].speed_cstr      = mach;			
			call(func {Polygon.selectSteer[0].setSpeed(mach, "mach")},nil, var err = []);# error in FG 2017.3.1 it seems. Worked in 2017.3.0. Fixed in 2018.1.1
			if (err != nil and size(err) > 0) {
				print("Harmless error M: "~err[0]);
			}
		}
	},

	setAlt: func (alt) {
		if (Polygon.selectSteer != nil and Polygon.editDetail) {
			#Polygon.selectSteer[0].alt_cstr      = alt;
			#Polygon.selectSteer[0].alt_cstr_type = "at";
			call(func {Polygon.selectSteer[0].setAltitude(alt, "at")},nil, var err = []);# error in FG 2017.3.1 it seems. Worked in 2017.3.0. Fixed in 2018.1.1
			if (err != nil and size(err) > 0) {
				print("Harmless error A: "~err[0]);
			}
		}
	},

	deleteSteerpoint: func {
		if (Polygon.selectSteer != nil and Polygon.editDetail == FALSE) {
			Polygon.appendSteer = FALSE;
			Polygon.insertSteer = FALSE;
			Polygon.editSteer   = FALSE;
			Polygon._apply = TRUE;
			if (Polygon.selectSteer[1] == 0 and Polygon.editing.plan.departure != nil) {
				Polygon.editing.plan.departure = nil;
			} elsif (Polygon.selectSteer[1] == Polygon.editing.getSize()-1 and Polygon.editing.plan.destination != nil) {
				Polygon.editing.plan.destination = nil;
			} else {
				Polygon.editing.plan.deleteWP(Polygon.selectSteer[1]);
			}
			Polygon._setDestDep(Polygon.editing);
			Polygon.selectSteer = nil;
			Polygon._apply = FALSE;
			printDA("toggle delete. ");
			return TRUE;
		}
		return FALSE;
	},

	insertSteerpoint: func () {
		if (Polygon.selectSteer != nil and !Polygon.editing.isFull() and Polygon.editDetail == FALSE) {
			Polygon.appendSteer = FALSE;
			Polygon.insertSteer = !Polygon.insertSteer;
			Polygon.editSteer = FALSE;
			printDA("toggle insert: "~Polygon.insertSteer);
		}
		return Polygon.insertSteer;
	},

	insertApply: func (lati, long) {
		if (Polygon.insertSteer and !Polygon.editing.isFull()) {
			Polygon._apply = TRUE;
			# TODO: what about name??!
			me.newName = sprintf("%s%d", Polygon.editing.getName(), (Polygon.selectSteer[1]+rand())*100);
			me.newSteerpoint = createWP({lat:lati,lon:long},me.newName,"pseudo");
			
			if (Polygon.selectSteer[1] == 0 and Polygon.editing.plan.departure != nil) {
				# replace departure with regular waypoint
				printDA("insert: clear dep");
				me.firstWP = Polygon.editing.plan.getWP(0);
				me.firstWP = createWP({lat: me.firstWP.lat, lon: me.firstWP.lon}, me.firstWP.id, "pseudo");
				Polygon.editing.plan.departure = nil;
				printDA("inserting old dep as navaid");
				#me.lastWP.wp_type = "navaid";#will prevent it from being cleared as a star/approach in future.
				Polygon.editing.plan.insertWP(me.firstWP,0);
			}
			Polygon.editing.plan.insertWP(me.newSteerpoint, Polygon.selectSteer[1]);
			Polygon.selectSteer = nil;
			Polygon.insertSteer = !Polygon.insertSteer;
			Polygon._apply = FALSE;
		} else {
			Polygon.insertSteer = FALSE;
		}
	},

	appendSteerpoint: func () {
		if (Polygon.editing != nil and !Polygon.editing.isFull() and Polygon.editDetail == FALSE) {
			Polygon.insertSteer = FALSE;
			Polygon.appendSteer = !Polygon.appendSteer;
			Polygon.editSteer = FALSE;
			printDA("toggle append: "~Polygon.appendSteer);
		}
		return Polygon.appendSteer;
	},

	appendApply: func (lati, long) {
		if (Polygon.appendSteer and !Polygon.editing.isFull()) {
			Polygon._apply = TRUE;
			# TODO: what about name??!
			me.newName = sprintf("%s%d", Polygon.editing.getName(), (Polygon.editing.getSize()+rand())*100);
			me.newSteerpoint = createWP({lat:lati,lon:long},me.newName,"pseudo");
			me.lastWP = nil;
			if (Polygon.editing.plan.destination != nil) {
				me.lastWP = Polygon.editing.plan.getWP(Polygon.editing.getSize()-1);
				printDA("append: dest != nil and last "~(me.lastWP!= nil));
				me.lastWP = createWP({lat: me.lastWP.lat, lon: me.lastWP.lon}, me.lastWP.id, "pseudo");
				Polygon.editing.plan.destination = nil;# this will make the delegate clear wp from list.
				Polygon.editing.plan.appendWP(me.lastWP);
			}
			Polygon.editing.plan.appendWP(me.newSteerpoint);
			Polygon.selectSteer = [Polygon.editing.plan.getWP(Polygon.editing.getSize()-1), Polygon.editing.getSize()-1];
			Polygon._apply = FALSE;

		} else {
			Polygon.appendSteer = FALSE;
		}
	},

	editSteerpointStop: func () {
		Polygon.editSteer = FALSE;
		Polygon.appendSteer = FALSE;
		Polygon.insertSteer = FALSE;
		Polygon.editDetail = FALSE;
	},

	setToggleAreaEdit: func {
		printDA("area edit");
		var poly = Polygon.polys["OP1"]; #TODO: temp stuff
		if (poly != Polygon.editing) {
			Polygon.editing = poly;
		} else {
			Polygon.editing = nil;
		}
		Polygon.editSteer = FALSE;
		Polygon.appendSteer = FALSE;
		Polygon.insertSteer = FALSE;
		Polygon.editDetail = FALSE;
		Polygon.selectSteer = nil;
		Polygon.editBullsEye = FALSE;
	},

	setToggleBEEdit: func {
		printDA("bulls-eye edit");
		Polygon.editing = nil;
		Polygon.editSteer = FALSE;
		Polygon.appendSteer = FALSE;
		Polygon.insertSteer = FALSE;
		Polygon.editDetail = FALSE;
		Polygon.selectSteer = nil;
		Polygon.editBullsEye = !Polygon.editBullsEye;
	},

	editPlan: func (poly) {
		if (poly != Polygon.editing) {
			Polygon.editSteer = FALSE;
			Polygon.appendSteer = FALSE;
			Polygon.insertSteer = FALSE;
			Polygon.editDetail = FALSE;
			#if (Polygon.polyEdit) {
			#	dap.set237(FALSE);
			#}
			#Polygon.polyEdit    = FALSE;
			Polygon.selectSteer = nil;
			Polygon.editing = poly;
		}	
		Polygon.editBullsEye = FALSE;	
	},

	_planEdited: func {
		if (Polygon._apply == FALSE) {
			removelistener(me.selectL);
			me.selectL = nil;
			printDA("plan edited, edit cancelled.");
			Polygon.editSteer = FALSE;
			Polygon.appendSteer = FALSE;
			Polygon.editDetail = FALSE;
			Polygon.insertSteer = FALSE;
			#Polygon.polyEdit    = FALSE;
			Polygon.selectSteer = nil;
			return;
		}
		#printDA("plan not edited!!!");
	},

	getLandingBase: func {
		return Polygon.flyRTB.getBase();
	},

	isLandingBaseRunwayActive: func {
		if (Polygon.flyRTB == Polygon.primary and Polygon.isPrimaryActive() == TRUE and Polygon.primary.plan.destination_runway != nil and Polygon.primary.getSize()-1==Polygon.primary.plan.current) {
			return TRUE;
		}
	},

	startPrimary: func {
		fgcommand("activate-flightplan", props.Node.new({"activate": 1}));
	},

	activateLandingBase: func {
		me.base = Polygon.getLandingBase();
		Polygon.flyRTB.setAsPrimary();
		if (me.base != nil) {
			printDA("activateLandingBase: found base");
			if(Polygon.primary.forceRunway()) {
				printDA("activateLandingBase: found runway, forced on");
				Polygon.startPrimary();#TODO: revisit all this, and logic in ladning mdoe for this. What should happen when there is no runway found?
			} else {
				printDA("activateLandingBase: did not find runway");
			}
			Polygon.primary.plan.current = Polygon.primary.getSize()-1;
			return TRUE;
		} else {
			printDA("activateLandingBase: did not find base");
			Polygon.stopPrimary();
			return FALSE;
		}
	},

	stopPrimary: func {
		fgcommand("activate-flightplan", props.Node.new({"activate": 0}));
	},

	isPrimaryActive: func {
		return getprop("autopilot/route-manager/active");
	},

	_setupListeners: func {
		setlistener("autopilot/route-manager/signals/flightplan-changed", func {Polygon._planExchange()});
	},

	_planExchange: func {
		printDA("plan exhanged");
		if (Polygon._activating == TRUE) {
			printDA("..it was planned");
		} else {
			# New plan was loaded in route-manager
			var poly = Polygon.primary;
			poly.plan = flightplan();
			poly.plan.id = poly.name;
			#me.alreadyApply = Polygon._apply;
			#Polygon._apply = TRUE;
			Polygon._setDestDep(poly);
			#Polygon._apply = me.alreadyApply;
			printDA("..it was unexpected");
		}
		if (Polygon.primary == Polygon.editing) {
			Polygon.editSteer = FALSE;
			Polygon.appendSteer = FALSE;
			Polygon.insertSteer = FALSE;
			Polygon.selectSteer = nil;
		}
	},

	_setDestDep: func (poly) {
		if (poly.type == TYPE_RTB or poly.type == TYPE_MIX) {
			# prioritize setting dest on rtb/mix
			if (poly.plan.destination == nil and poly.getSize()>0) {
				me.lookupID = poly.plan.getWP(poly.getSize()-1).id;
				if (me.lookupID != nil) {
					me.airport = airportinfo(me.lookupID);
					if (me.airport != nil and ghosttype(me.airport) == "airport") {
						poly.plan.deleteWP(poly.getSize()-1);
						poly.plan.destination = me.airport;
					}
				}
			}
			if (poly.plan.departure == nil and poly.getSize()>1) {
				me.lookupID = poly.plan.getWP(0).id;
				if (me.lookupID != nil) {
					me.airport = airportinfo(me.lookupID);
					if (me.airport != nil and ghosttype(me.airport) == "airport") {
						poly.plan.deleteWP(0);
						poly.plan.departure = me.airport;
					}
				}
			}
		}
		if (poly.type == TYPE_MISS) {
			# prioritize setting dep on mission
			if (poly.plan.departure == nil and poly.getSize()>0) {
				me.lookupID = poly.plan.getWP(0).id;
				if (me.lookupID != nil) {
					me.airport = airportinfo(me.lookupID);
					if (me.airport != nil and ghosttype(me.airport) == "airport") {
						poly.plan.deleteWP(0);
						poly.plan.departure = me.airport;
					}
				}
			}
			if (poly.plan.destination == nil and poly.getSize()>1) {
				me.lookupID = poly.plan.getWP(poly.getSize()-1).id;
				if (me.lookupID != nil) {
					me.airport = airportinfo(me.lookupID);
					if (me.airport != nil and ghosttype(me.airport) == "airport") {
						poly.plan.deleteWP(poly.getSize()-1);
						poly.plan.destination = me.airport;
					}
				}
			}
		}
	},

	_finishedPrimary: func (pln) {
		#called from RouteManagerDelegate
		var plns="";
		if (pln.id != nil) {
			plns = pln.id;
		}
		printDA("plan finished: "~plns);
		if (Polygon._activating == FALSE and plns == Polygon.primary.getName()) {
			if (Polygon.primary.type == TYPE_MISS) {
				Polygon.flyRTB.setAsPrimary();
				Polygon.startPrimary();
				printDA("..starting "~Polygon.flyRTB.getName());
			} elsif (Polygon.primary.type == TYPE_RTB and Polygon.primary.getSize() > 0) {
				Polygon.startPrimary();
				Polygon.selectDestinationOnPrimary();
				printDA("..restarted last on "~Polygon.primary.getName());
			}
		} else {
			printDA("..it was deactivated. Nothing to worry about.");
		}
		# TODO Handle if finish is called just from activating another.
	},

	selectDestinationOnPrimary: func {
		Polygon.primary.plan.current = Polygon.primary.plan.getPlanSize()-1;
		return Polygon.primary.plan.getPlanSize() != 0;
	},

	#
	# Instance methods and variables
	#
	new: func (nameNum, nameVari, type, xml, default = 0) {
		var newPoly = { parents : [Polygon]};
		if (default == 1) {
			newPoly.plan = flightplan();
		} elsif (xml != nil) {
			newPoly.plan = nil;
			call(func {newPoly.plan = createFlightplan(xml);}, nil, var err = []);
			if (size(err)) {
				print(err[0]);
				print("That plan will be init empty.");
			}
			if (newPoly.plan == nil) {
				newPoly.plan = createFlightplan();
			}
		} else {
			newPoly.plan = createFlightplan();
		}
		newPoly.plan.id = nameNum~nameVari;
		newPoly.name = nameNum~nameVari;
		newPoly.nameNum = nameNum;
		newPoly.nameVari = nameVari;
		newPoly.type = type;
		newPoly.color = COLOR_GREY_LIGHT;
		return newPoly;
	},

	isFull: func {
		return (me.type == TYPE_AREA and me.getSize()>=maxLV) or (me.type != TYPE_AREA and me.getSize()>=maxSteers);
	},

	getName: func {
		return me.name;
	},

	getNameNumber: func {
		return me.nameNum;
	},

	getNameVariant: func {
		return me.nameVari;
	},

	getPolygon: func {
		me.numbers = me.plan.getPlanSize();
		me.polygon = [];
		for (var i = 0; i < me.numbers; i+=1) {
			append(me.polygon, me.plan.getWP(i));
		}
		return me.polygon;
	},

	getSteerpoint: func {
		if (me.plan.current == me.getSize()-1 and me.plan.destination_runway != nil and me.plan.destination != nil) {
			return [me.plan.destination_runway, me.plan.destination];
		}
		if (me.plan.current == me.getSize()-1 and me.plan.destination != nil) {
			return [me.plan.destination];
		}
		if (me.plan.current == 0 and me.plan.departure_runway != nil and me.plan.departure != nil) {
			return [me.plan.departure_runway, me.plan.departure];
		}
		if (me.plan.current == 0 and me.plan.departure != nil) {
			return [me.plan.departure];
		}
		return [me.plan.currentWP()];
	},

	getIndex: func {
		return me.plan.current;
	},

	getLeg: func {
		return me.plan.currentWP();
	},

	setAsPrimary: func {
		if (!me.isPrimary() and me.type != TYPE_AREA) {
			printDA("Polygon._activating = TRUE;");
			Polygon._activating = TRUE;
			Polygon.primary = me;
			printDA("activating plan "~me.getName());
			me.plan.activate();
			printDA("Polygon._activating = FALSE;");
			Polygon._activating = FALSE;
		}
	},

	isPrimary: func {
		return Polygon.primary == me;
	},

	getSize: func {
		return me.plan.getPlanSize();
	},

	cycle: func {
		# Cycle waypoints
		if (me.plan.current == me.getSize()-1) {
			me.plan.current = 0;
		} else {
			me.plan.current = me.plan.current +1;
		}
	},

	getBase: func {
		# Will return destination or last waypoint (if its a airport).
		if (me.getSize() > 0) {
			if(me.plan.destination != nil) {
				printDA("getBase returning dest which is airport "~me.plan.destination.id);
				return me.plan.destination;
			} else {
				me.base = me.plan.getWP(me.getSize()-1);
				if (ghosttype(me.base) == "airport") {
					printDA("getBase returning "~(me.getSize()-1)~" which is airport "~me.base.id);
					return me.base;
				} else {
					printDA("getBase: RTB does not have airport as last steerpoint.");
				}
			}
		}
		return nil;
	},

	forceRunway: func {
		# will only force a runway onto a destination.
		me.base = me.plan.destination;
		me.baseRwy = me.plan.destination_runway;
		if (me.baseRwy == nil and me.base != nil) {
			me.runways = me.base.runways;
	        me.runwaysVector = [];
	        foreach (var runwayKey ; keys(me.runways)) {
	            append(me.runwaysVector, me.runways[runwayKey]);
	        }
	        if (size(me.runwaysVector)!=0) {
	        	me.plan.destination_runway = me.runwaysVector[0];
	        	return TRUE;
	        }
		} elsif (me.baseRwy != nil) {
			return TRUE;
		}
		return FALSE;
	},

	cycleDestinationRunway: func {
		# cycle through destination runways.
		me.base = me.plan.destination;
		me.baseRwy = me.plan.destination_runway;
		me.shouldStart = me.isPrimary() == TRUE and Polygon.isPrimaryActive() == TRUE;
		if (me.base != nil) {
			me.runways = me.base.runways;
	        me.runwaysVector = [];
	        foreach (var runwayKey ; keys(me.runways)) {
	            append(me.runwaysVector, me.runways[runwayKey]);
	        }
	        if (size(me.runwaysVector)==0) {
	        	return FALSE;
	        }
	        me.currRWY = -1;
	        if (me.baseRwy != nil) {
		        for (var i = 0; i<size(me.runwaysVector);i+=1) {
		            if (me.runwaysVector[i].id == me.baseRwy.id) {
		                me.currRWY = i;
		                break;
		            }
		        }
		    }
	        me.currRWY += 1;
	        if (me.currRWY >= size(me.runwaysVector)) {
	            me.currRWY = 0;
	        }
	        me.plan.destination_runway = me.runwaysVector[me.currRWY];	 
	        if (me.shouldStart == TRUE) {
	        	Polygon.startPrimary();
	        	me.plan.current = me.getSize()-1;
	        }
	        return TRUE;
		} else {
			return FALSE;
		}
	},

	loop: func {
		dap.posOutDisplay = "       ";
		if (Polygon.isPrimaryActive()) {
			me.steer = Polygon.primary.getSteerpoint();
			if (me.steer != nil) {
				me.distance = getprop("autopilot/route-manager/wp/dist");
				if(me.distance != nil) {
					if (ghosttype(me.steer[0]) == "runway" or ghosttype(me.steer[0]) == "airport") {
						me.distance = me.distance*NM2M*0.001;
						dap.posOutDisplay = sprintf(" 10%03d0",me.distance);
					} else {
						me.distance = me.distance*NM2M*0.001;
						dap.posOutDisplay = sprintf(" 00%03d0",me.distance);
					}
				}
			}
		}
	},
};

var poly_start = func {
	#removelistener(lsnr);
	if (getprop("ja37/systems/variant") == 0) {
		Polygon.setupJAPolygons();
	} else {
		Polygon.setupAJPolygons();
	}
}

#var lsnr = setlistener("ja37/supported/initialized", poly_start);
