//
//  WorkoutMapViewManager.swift
//
//  OutRun
//  Copyright (C) 2020 Tim Fraedrich <timfraedrich@icloud.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import UIKit
import MapKit
import CoreLocation
import AMapFoundationKit
import AMapLocationKit

enum WorkoutMapViewManager {
    
    static func setupRoute(forWorkout workout: Workout, mapView: MKMapView, customEdgePadding: UIEdgeInsets = UIEdgeInsets(top: 40, left: 20, bottom: 40, right: 20), completion: @escaping () -> Void) {
        
//        AMapServices.shared().apiKey = "2c59f389d8e55b33a04f6c5ed1be2242";
        var route = MKPolyline()
//        print(workout.routeData.coreStoreDumpString)
        let coordinates = workout.routeData.map({ (sample) -> CLLocationCoordinate2D in
                        
            let gpscoord = CLLocationCoordinate2D(latitude: sample.latitude, longitude: sample.longitude)
            let amapcoord = AMapCoordinateConvert(gpscoord, AMapCoordinateType.GPS);
            return amapcoord

        })
        route = MKPolyline(coordinates: coordinates, count: coordinates.count)
        mapView.delegate = WorkoutMapViewDelegate.standard
        mapView.addOverlay(route)
        mapView.setVisibleMapRect(route.boundingMapRect, edgePadding: customEdgePadding, animated: true)
        completion()
    }
    
}
