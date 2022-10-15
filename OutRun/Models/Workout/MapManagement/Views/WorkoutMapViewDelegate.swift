//
//  WorkoutMapViewDelegate.swift
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

class WorkoutMapViewDelegate: NSObject, MKMapViewDelegate {
    
    static let standard = WorkoutMapViewDelegate()
    
//    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
//        let renderer = MKPolylineRenderer(overlay: overlay)
//        renderer.strokeColor = .accentColor
//        renderer.lineWidth = 8.0
//
//        return renderer
//    }
    
    func mapViewDidFinishLoadingMap(_ mapView: MKMapView) {
        
//        let cl = CLLocationCoordinate2D.init(latitude: 40.050868598090275, longitude: 116.3177281358507)
//        let p = mapView.convert(cl, toPointTo: mapView)
//        print("cl=",cl,"p=",p)
        
        let overlay = mapView.overlays[0];
        let polyline = overlay as! MKPolyline
        let mkmapPoints = polyline.points()
                
        var coordinates = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid,
                                                   count: polyline.pointCount)
        polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: polyline.pointCount))
        
        

//        for index in 0 ..< polyline.pointCount {
//
//            let mkmapPoint = mkmapPoints[index]
//            let coordinate = coordinates[index]
//            let cgpoint = mapView.convert(coordinate, toPointTo: mapView)
//            print("mkmapPoint= \(mkmapPoint) ; coordinate=\(coordinate.longitude),\(coordinate.latitude); cgpoint=\(cgpoint)")
//
//        }
        
        
        let cgpoints = coordinates.map({ (coord) -> CGPoint in
                    print(coord)
                    let cgpoint = mapView.convert(coord, toPointTo: mapView)
                    print(cgpoint)
                    return cgpoint
                })
        
        let cgmutablePath = CGMutablePath()
        cgmutablePath.addLines(between: cgpoints)
        
        let pathLayer = CAShapeLayer()
        pathLayer.strokeColor = UIColor.red.cgColor
        pathLayer.fillColor = UIColor.clear.cgColor
        pathLayer.lineJoin = CAShapeLayerLineJoin.round
        pathLayer.path = cgmutablePath
        
        let animation = CABasicAnimation()
        animation.keyPath = "strokeEnd"
        animation.duration = 5
        animation.fromValue = 0.0
        animation.toValue = 1.0
        animation.timingFunction = CAMediaTimingFunction.init(name: CAMediaTimingFunctionName.easeInEaseOut)
        animation.fillMode = CAMediaTimingFillMode.forwards
        animation.isRemovedOnCompletion = false
        
        pathLayer.add(animation, forKey: "strokeEnd")
        
        
        let headImage = UIImage(systemName: "figure.outdoor.cycle")
        let imageLayer = CALayer()
        imageLayer.contents = headImage!.cgImage
        imageLayer.anchorPoint = CGPointZero;
        imageLayer.frame = CGRectMake(0.0, 0.0, headImage!.size.width, headImage!.size.height);
        
        pathLayer.addSublayer(imageLayer)
        
        let headAnimation = CAKeyframeAnimation()
        headAnimation.keyPath = "position"
        headAnimation.duration = 5
        headAnimation.isRemovedOnCompletion = false
        headAnimation.path = cgmutablePath;
        headAnimation.calculationMode = CAAnimationCalculationMode.paced;
//        headAnimation.delegate =
        headAnimation.timingFunction = CAMediaTimingFunction.init(name: CAMediaTimingFunctionName.easeInEaseOut)

        imageLayer.add(headAnimation, forKey: "position")
        
        mapView.layer.addSublayer(pathLayer)
        
        
    }

    
}

