//
//  DataManager.swift
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

import Foundation
import CoreStore
import CoreLocation
import HealthKit

struct DataManager {
    
    /// static optional instance of the local storage holding the workout data
    private static var storage: SQLiteStore?
    
    /// The size of the local storage in bytes; if `nil` it could not be calculated.
    public static var diskSize: Int? {
        if let size = storage?.fileSize() {
            return Int(size)
        }
        return nil
    }
    
    /**
     The primary `DataStack` used by the `DataManager`.
     - warning: make sure `dataStack` is initialised by calling `DataManager.setup(dataModel:completion:migration:)` accessing the property will lead to a fatal error otherwise
     */
    public static var dataStack: DataStack!
    
    /**
     This function sets up the data management by initialising the `dataStack` and loading the underlying sqlite storage of the database
     - parameter dataModel: an `ORDataModel` conforming `Type` being used to setup the data management
     - parameter completion: the closure being called on a successful completion of setting up data management
     - parameter migration: the closure being called on the event of a migration happening, including a `Progress` object indicating the progress of the migration
     - warning: If this method fails it does so in a fatal error, the app will crash as a result.
     */
    public static func setup(dataModel: ORDataModel.Type, completion: @escaping (DataManager.SetupError?) -> Void, migration: @escaping (Progress) -> Void) {
        
        
        let completion: (DataManager.SetupError?) -> Void = { error in
            DispatchQueue.main.async {
                completion(error)
            }
        }
        
        // setup storage
        let storage = SQLiteStore(
            fileName: "OutRun.sqlite",
            migrationMappingProviders: dataModel.migrationChain.compactMap(
                { (type) -> CustomSchemaMappingProvider? in
                    return type.mappingProvider
                }
            ),
            localStorageOptions: .none
        )
        self.storage = storage
        
        // select relevant versions
        let currentVersion = storage.currentORModel(from: dataModel.migrationChain)
        var relevants = dataModel.migrationChain.filter { (type) -> Bool in
            // relevent version should include the final type (dataModel) and all intermediate models, but it is important that they are successors of current version of the storage otherwise the models might be incompatible
            (type.self is ORIntermediateDataModel.Type || type == dataModel) && (currentVersion != nil ? type.isSuccessor(to: currentVersion!) : true)
        }
            
        let destinationModel = relevants.removeFirst()
        dataStack = DataStack(oRMigrationChain: dataModel.migrationChain, oRDataModel: destinationModel)
        
        // adding storage
        if let progress = dataStack.addStorage(
            storage,
            completion: { result in
                switch result {
                case .success(_):
                    
                    if let intermediate = destinationModel as? ORIntermediateDataModel.Type {
                        if !intermediate.intermediateMappingActions(dataStack) {
                            print("[DataManager] Intermediate mapping actions of \(destinationModel) were unsuccessful")
                            completion(.intermediateMappingActionsFailed(version: intermediate))
                            return
                        }
                    }
                    
                    if relevants.first != nil {
                        setup(dataModel: dataModel, completion: completion, migration: migration)
                    } else {
                        completion(nil)
                    }
                    
                case .failure(let error):
                    print("[DataManager] Failed to add storage for \(dataModel)\nError: \(error)")
                    completion(.failedToAddStorage(error: error))
                }
            }
        ) {
            // handling migration
            DispatchQueue.main.async {
                migration(progress)
            }
        }
    }
    
    /**
     This function saves a workout to the database.
     - parameter object: the data set to be saved to the database
     - parameter completion: the closure being executed on the main thread as soon as the saving either succeeds or fails
     - parameter success: indicates the success of saving the workout
     - parameter error: gives more detailed information on an error if one occured
     - parameter workout: holds the `Workout` if saving it succeeded
     - note: Objects conforming to `OREventInterface` and associated with the provided object will not be added to the database
     - warning: An `object` of Type `Workout` will be rejected with an `.alreadySaved` error, because all objects of that type must already be in the database.
     */
    public static func saveWorkout(
        object: ORWorkoutInterface,
        completion: @escaping (_ success: Bool, _ error: DataManager.SaveError?, _ workout: Workout?) -> Void) {
        
        let completion: (Bool, DataManager.SaveError?, Workout?) -> Void = { success, error, workout in
            DispatchQueue.main.async {
                completion(success, error, workout)
            }
        }
        
        saveWorkouts(
            objects: [object],
            completion: { success, error, workouts in
                if let workout = workouts.first {
                    completion(true, nil, workout)
                } else {
                    
                    switch error {
                    case .notAllSaved:
                        completion(false, .alreadySaved, nil)
                    case .notAllValid:
                        completion(false, .notValid, nil)
                    case .databaseError(let error):
                        completion(false, .databaseError(error: error), nil)
                    default:
                        // this case should never occur
                        completion(false, nil, nil)
                    }
                }
            }
        )
    }
    
    /**
     This function saves multiple workouts to the database.
     - parameter objects: the data sets to be saved to the database
     - parameter completion: the closure being executed on the main thread as soon as the saving either succeeds or fails
     - parameter success: indicates the success of saving workouts; this will also be `true` if not all workouts were valid and some have been excluded
     - parameter error: gives more detailed information on an error if one occured
     - parameter workouts: holds the `Workout`s that were successfully saved
     - note: Objects conforming to `OREventInterface` and associated with the provided objects will not be added to the database
     - warning: Objects of type `Workout` will be rejected, because all objects of that type must already be in the database.
     */
    public static func saveWorkouts(
        objects: [ORWorkoutInterface],
        completion: @escaping (_ success: Bool, _ error: DataManager.SaveMultipleError?, _ workouts: [Workout]) -> Void) {
        
        let completion: (Bool, DataManager.SaveMultipleError?, [Workout]) -> Void = { success, error, workouts in
            DispatchQueue.main.async {
                completion(success, error, workouts)
            }
        }
        
        // filtering for Workout class and already saved
        let filteredObjects = objects.filter { (object) -> Bool in
            if object is Workout {
                return false
            } else if let uuid = object.uuid, workoutHasDuplicate(uuid: uuid) {
                return false
            }
            return true
        }
        
        // Todo: Validation
        let validatedObjects = filteredObjects
        
        dataStack.perform(asynchronous: { (transaction) -> [Workout] in
            
            var workouts = [Workout]()
            
            for object in validatedObjects {
                
                let workout = transaction.create(Into<Workout>())
                workout._uuid .= object.uuid ?? UUID()
                workout._workoutType .= object.workoutType
                workout._distance .= object.distance
                workout._steps .= object.steps
                workout._startDate .= object.startDate
                workout._endDate .= object.endDate
                workout._burnedEnergy .= object.burnedEnergy
                workout._isRace .= object.isRace
                workout._comment .= object.comment
                workout._isUserModified .= object.isUserModified
                workout._healthKitUUID .= object.healthKitUUID
                
                workout._ascend .= object.ascend
                workout._descend .= object.descend
                workout._activeDuration .= object.activeDuration
                workout._pauseDuration .= object.pauseDuration
                workout._dayIdentifier .= object.dayIdentifier
                
                for tempPause in object.pauses {
                    let pause = transaction.create(Into<WorkoutPause>())
                    pause._uuid .= tempPause.uuid ?? UUID()
                    pause._startDate .= tempPause.startDate
                    pause._endDate .= tempPause.endDate
                    pause._pauseType .= tempPause.pauseType
                    
                    pause._workout .= workout
                }
                
                for tempWorkoutEvent in object.workoutEvents {
                    let workoutEvent = transaction.create(Into<WorkoutEvent>())
                    workoutEvent._uuid .= tempWorkoutEvent.uuid ?? UUID()
                    workoutEvent._eventType .= tempWorkoutEvent.eventType
                    workoutEvent._timestamp .= tempWorkoutEvent.timestamp
                    
                    workoutEvent._workout .= workout
                }

                for tempSample in object.routeData {
                    let routeSample = transaction.create(Into<WorkoutRouteDataSample>())
                    routeSample._uuid .= tempSample.uuid ?? UUID()
                    routeSample._latitude .= tempSample.latitude
                    routeSample._longitude .= tempSample.longitude
                    routeSample._altitude .= tempSample.altitude
                    routeSample._timestamp .= tempSample.timestamp
                    routeSample._horizontalAccuracy .= tempSample.horizontalAccuracy
                    routeSample._verticalAccuracy .= tempSample.verticalAccuracy
                    routeSample._speed .= tempSample.speed
                    routeSample._direction .= tempSample.direction
                    
                    routeSample._workout .= workout
                }
                
                for tempSample in object.heartRates {
                    let heartRateSample = transaction.create(Into<WorkoutHeartRateDataSample>())
                    heartRateSample._uuid .= tempSample.uuid ?? UUID()
                    heartRateSample._heartRate .= tempSample.heartRate
                    heartRateSample._timestamp .= tempSample.timestamp
                    
                    heartRateSample._workout .= workout
                }
                
                workouts.append(workout)
                
            }
            
            return workouts
            
        }) { (result) in
            switch result {
            case .success(let tempWorkouts):
                let workouts = dataStack.fetchExisting(tempWorkouts)
                
                if workouts.count == objects.count {
                    completion(true, nil, workouts)
                } else if workouts.count == filteredObjects.count {
                    completion(true, .notAllSaved, workouts)
                } else {
                    // last case: workouts.count must be equal to validatedObjects.count
                    completion(true, .notAllValid, workouts)
                }
                
            case .failure(let error):
                completion(false, .databaseError(error: error), [])
            }
        }
        
    }
    
    /**
     This function updates a workout from a data set referencing the workout with its universally unique identifier.
     - parameter object: the data set containing all updates
     - parameter completion: the closure being perfomed upon finishing the updating process
     - parameter success: indicates the success of the operation
     - parameter error: gives more detailed information on an error if one occured
     - parameter workout: holds the `Workout` if updating it succeeded
     - warning: Objects of type `Workout` will be rejected, because all objects of that type must already hold the provided data.
     */
    public static func updateWorkout(object: ORWorkoutInterface, completion: @escaping (_ success: Bool, _ error: DataManager.UpdateError?, _ workout: Workout?) -> Void) {
        
        let completion: (Bool, DataManager.UpdateError?, Workout?) -> Void = { success, error, workout in
            DispatchQueue.main.async {
                completion(success, error, workout)
            }
        }
        
        // check for Workout class
        if object is Workout {
            completion(false, .notAltered, nil)
            return
        }
        
        // check for uuid {
        if object.uuid == nil {
            completion(false, .notSaved, nil)
            return
        }
        
        // Todo: Validation
        
        dataStack.perform(asynchronous: { (transaction) -> Workout? in
            
            if let workoutObject = try? transaction.fetchOne(From<Workout>().where(\._uuid == object.uuid)), let workout = transaction.edit(workoutObject) {
                
                workout._uuid .= object.uuid ?? UUID()
                workout._workoutType .= object.workoutType
                workout._distance .= object.distance
                workout._steps .= object.steps
                workout._startDate .= object.startDate
                workout._endDate .= object.endDate
                workout._burnedEnergy .= object.burnedEnergy
                workout._isRace .= object.isRace
                workout._comment .= object.comment
                workout._isUserModified .= object.isUserModified
                workout._healthKitUUID .= object.healthKitUUID
                
                workout._ascend .= object.ascend
                workout._descend .= object.descend
                workout._activeDuration .= object.activeDuration
                workout._pauseDuration .= object.pauseDuration
                workout._dayIdentifier .= object.dayIdentifier
                
                for tempPause in object.pauses where tempPause.uuid == nil {
                    let pause = transaction.create(Into<WorkoutPause>())
                    pause._uuid .= tempPause.uuid ?? UUID()
                    pause._startDate .= tempPause.startDate
                    pause._endDate .= tempPause.endDate
                    pause._pauseType .= tempPause.pauseType
                    
                    pause._workout .= workout
                }
                
                for tempWorkoutEvent in object.workoutEvents where tempWorkoutEvent.uuid == nil {
                    let workoutEvent = transaction.create(Into<WorkoutEvent>())
                    workoutEvent._uuid .= tempWorkoutEvent.uuid ?? UUID()
                    workoutEvent._eventType .= tempWorkoutEvent.eventType
                    workoutEvent._timestamp .= tempWorkoutEvent.timestamp
                    
                    workoutEvent._workout .= workout
                }

                for tempSample in object.routeData where tempSample.uuid == nil {
                    let routeSample = transaction.create(Into<WorkoutRouteDataSample>())
                    routeSample._uuid .= tempSample.uuid ?? UUID()
                    routeSample._latitude .= tempSample.latitude
                    routeSample._longitude .= tempSample.longitude
                    routeSample._altitude .= tempSample.altitude
                    routeSample._timestamp .= tempSample.timestamp
                    routeSample._horizontalAccuracy .= tempSample.horizontalAccuracy
                    routeSample._verticalAccuracy .= tempSample.verticalAccuracy
                    routeSample._speed .= tempSample.speed
                    routeSample._direction .= tempSample.direction
                    
                    routeSample._workout .= workout
                }
                
                for tempSample in object.heartRates where tempSample.uuid == nil {
                    let heartRateSample = transaction.create(Into<WorkoutHeartRateDataSample>())
                    heartRateSample._uuid .= tempSample.uuid ?? UUID()
                    heartRateSample._heartRate .= tempSample.heartRate
                    heartRateSample._timestamp .= tempSample.timestamp
                    
                    heartRateSample._workout .= workout
                }
                
                return workout
                
            } else {
                return nil
            }
            
        }) { (result) in
            switch result {
            case .success(let tempWorkout):
                if let tempWorkout = tempWorkout, let workout = dataStack.fetchExisting(tempWorkout) {
                    completion(true, nil, workout)
                } else {
                    completion(false, .databaseError(error: CoreStoreError.persistentStoreNotFound(entity: Workout.self)), nil)
                }
            case .failure(let error):
                completion(false, .databaseError(error: error), nil)
            }
        }
    }
    
    /**
     Saves an event to the database.
     - parameter object: the data set to be saved to the database
     - parameter completion: the closure being executed on the main thread as soon as the saving either succeeds or fails
     - parameter success: indicates the success of saving the event
     - parameter error: gives more detailed information on an error if one occured
     - parameter event: holds the `Event` if saving it succeeded
     - note: Objects conforming to `ORWorkoutInterface` and associated with the provided data sets will not be added to the database, rather the data manager will try to query workout objects from only the provided `UUID`s in the `ORWorkoutInterface` objects and attach them to the `Event`. For that it is improtant that these workout objects are already saved to the database, otherwise a reference cannot be established.
     - warning: An `object` of Type `Event` will be rejected with an `.alreadySaved` error, because all objects of that type must already be in the database.
     */
    public static func saveEvent(object: OREventInterface, completion: @escaping (_ success: Bool, _ error: DataManager.SaveError?, _ event: Event?) -> Void) {
        
        let completion: (Bool, DataManager.SaveError?, Event?) -> Void = { success, error, event in
            DispatchQueue.main.async {
                completion(success, error, event)
            }
        }
        
        saveEvents(
            objects: [object],
            completion: { success, error, events in
                if let event = events.first {
                    completion(true, nil, event)
                } else {
                    
                    switch error {
                    case .notAllSaved:
                        completion(false, .alreadySaved, nil)
                    case .notAllValid:
                        completion(false, .notValid, nil)
                    case .databaseError(let error):
                        completion(false, .databaseError(error: error), nil)
                    default:
                        // this case should never occur
                        completion(false, nil, nil)
                    }
                }
            }
        )
        
    }
    
    /**
     Saves multiple events to the database.
     - parameter objects: the data sets to be saved to the database
     - parameter completion: the closure being executed on the main thread as soon as the saving either succeeds or fails
     - parameter success: indicates the success of saving the events
     - parameter error: gives more detailed information on an error if one occured
     - parameter events: holds the `Event`s if saving them succeeded
     - note: Objects conforming to `ORWorkoutInterface` and associated with the provided data sets will not be added to the database, rather the data manager will try to query workout objects from only the provided `UUID`s in the `ORWorkoutInterface` objects and attach them to the `Event`s. For that it is improtant that these workout objects are already saved to the database, otherwise a reference cannot be established.
     - warning: `objects` of Type `Event` will be rejected with an `.alreadySaved` error, because all objects of that type must already be in the database.
     */
    public static func saveEvents(objects: [OREventInterface], completion: @escaping (_ success: Bool, _ error: DataManager.SaveMultipleError?, _ events: [Event]) -> Void) {
        
        let completion: (Bool, DataManager.SaveMultipleError?, [Event]) -> Void = { success, error, events in
            DispatchQueue.main.async {
                completion(success, error, events)
            }
        }
        
        let filteredObjects = objects.filter { (object) -> Bool in
            if object is Event {
                return false
            } else if let uuid = object.uuid, eventHasDuplicate(uuid: uuid) {
                return false
            }
            return true
        }
        
        // Todo: Validation
        let validatedObjects = filteredObjects
        
        dataStack.perform(asynchronous: { (transaction) -> [Event] in
            
            var events = [Event]()
            
            for object in validatedObjects {
                
                let event = transaction.create(Into<Event>())
                
                event._uuid .= object.uuid ?? UUID()
                event._title .= object.title
                event._comment .= object.comment
                event._startDate .= object.startDate
                event._endDate .= object.endDate
                
                let workoutUUIDs = object.workouts.compactMap { (workout) -> UUID? in
                    return workout.uuid
                }
                
                if let workouts = try? transaction.fetchAll(
                    From<Workout>()
                        .where({
                            Where<Workout>(workoutUUIDs.containsOptional($0.uuid))
                        })
                ) {
                    event._workouts .= workouts
                }
                
                events.append(event)
                
            }
            
            return events
        
        }) { (result) in
            switch result {
            case .success(let tempEvents):
                let events = dataStack.fetchExisting(tempEvents)
                completion(true, nil, events)
            case .failure(let error):
                completion(false, .databaseError(error: error), [])
            }
        }
    }
    
    // TODO: alter event; delete all
    
    /// A `CoreStore.ListMonitor` to observe changes in the database and refresh the `WorkoutListViewController`
    public static let workoutMonitor = dataStack.monitorList(
        From<Workout>()
            .orderBy(.descending(\._startDate))
            .where(Where<Workout>(true))
    )
    
}
