//
//  FirebaseManager+Queue.swift
//  grouplay
//
//  Created by Sam Lerner on 8/27/18.
//  Copyright © 2018 Sam Lerner. All rights reserved.
//

import Foundation
import Firebase
import FirebaseDatabase

extension FirebaseManager {
    
    // MARK: Getters
    
    // Fetch the approved and pending queues from the database for the given session.
    func fetchQueue(sess: Session, completion: @escaping (String?) -> Void) {
        if sessRef == nil {
            print("sess ref nil")
            completion("sess ref nil")
            return
        }
        sessRef?.child("queue").observeSingleEvent(of: .value, with: { snap in
            guard let queueDict = snap.value as? [String:AnyObject] else {
                completion("no snap val")
                return
            }
            if let approvedDict = queueDict["approved"] as? [String:AnyObject] {
                sess.approved = self.parseQueue(dict: approvedDict)
            }
            if let pendingDict = queueDict["pending"] as? [String:AnyObject] {
                sess.pending = self.parseQueue(dict: pendingDict)
            }
            completion(nil)
        })
    }
    
    func refresh() {
        guard sessRef != nil else {
            print("sess ref is nil")
            return
        }
        
        sessRef?.observeSingleEvent(of: .value, with: { snap in
            guard let val = snap.value as? [String:AnyObject] else { return }
            
            if let approvedDict = (val["queue"] as? [String:AnyObject])?["approved"] as? [String:AnyObject] {
                SessionStore.session?.approved = self.parseQueue(dict: approvedDict)
            }
            if let pendingDict = (val["queue"] as? [String:AnyObject])?["pending"] as? [String:AnyObject] {
                SessionStore.session?.approved = self.parseQueue(dict: pendingDict)
            }
            
            if let currDict = val["current"] as? [String:AnyObject] {
                guard let trackId = currDict["id"] as? String else { return }
                
                let currTrack = self.parseTrack(id: trackId, trackDict: currDict)
                guard let timeLeft = currDict["time_left"] as? Int,
                    let paused = currDict["paused"] as? Bool else { return }
                
                SessionStore.session?.current = (currTrack, timeLeft, currTrack.timestamp, !paused)
            }
        })
    }
    
    // MARK: Setters
    
    // Enqueue the given track in the database. If the current user is the owner, it is automatically set to approved. Otherwise, it is pending.
    func enqueue(_ track: Track, pending: Bool) {
        insert(track, pending: false, before: Date.now())
    }
    
    // Remove the given track from the database queue.
    func dequeue(_ track: Track, pending: Bool) {
        let pathExt = pending ? "pending" : "approved"
        sessRef?.child("queue").child(pathExt).child(track.trackID).removeValue()
    }
    
    // Insert into the queue before the given position for when the previous track is skipped
    func insert(_ track: Track, pending: Bool, before: UInt64) {
        let pathExt = pending ? "pending" : "approved"
        sessRef?.child("queue").child(pathExt).child(track.trackID).setValue([
            "title": track.title,
            "artist": track.artist,
            "imageURL": "\(track.albumImageURL)",
            "duration": track.duration,
            "timestamp": before-1
            ])
    }
    
    // MARK: Observers
    
    // Observe additions and removals from both the approved and pending queues.
    func observeQueue(sess: Session, eventOccurred: @escaping (Bool) -> Void) {
        guard sessRef != nil else {
            print("sess ref is nil")
            eventOccurred(false)
            return
        }
        observeQueuePathAdd(sess: sess, path: "approved", eventOccurred)
        observeQueuePathAdd(sess: sess, path: "pending", eventOccurred)
        observeQueuePathRemove(sess: sess, path: "approved", eventOccurred)
        observeQueuePathRemove(sess: sess, path: "pending", eventOccurred)
    }
    
    private func observeQueuePathAdd(sess: Session, path: String, _ eventOccurred: @escaping (Bool) -> Void) {
        sessRef!.child("queue").child(path).observe(.childAdded, with: { snap in
            guard let newTrackDict = snap.value as? [String:AnyObject] else {
                print("could not parse new track from snapshot: \(String(describing: snap.value))")
                eventOccurred(false)
                return
            }
            
            let newTrack = self.parseTrack(id: snap.key, trackDict: newTrackDict)
            var queue = path == "approved" ? sess.approved : sess.pending
            guard newTrack.trackID != "" && !queue.contains(where: { $0.trackID == newTrack.trackID }) else {
                //print("new track is nil or is already in approved queue")
                eventOccurred(false)
                return
            }
            
            queue.append(newTrack)
            if path == "approved" {
                SessionStore.session?.approved.append(newTrack)
            } else {
                SessionStore.session?.pending.append(newTrack)
            }
            eventOccurred(true)
        })
    }
    
    private func observeQueuePathRemove(sess: Session, path: String, _ eventOccurred: @escaping (Bool) -> Void) {
        sessRef!.child("queue").child(path).observe(.childRemoved, with: { snap in
            guard let newTrackDict = snap.value as? [String:AnyObject] else {
                print("could not parse new track from snapshot: \(String(describing: snap.value))")
                eventOccurred(false)
                return
            }
            
            let newTrack = self.parseTrack(id: snap.key, trackDict: newTrackDict)
            var queue = path == "approved" ? sess.approved : sess.pending
            guard newTrack.trackID != "" && queue.contains(where: { $0.trackID == newTrack.trackID }) else {
                //print("new track is nil or is already in approved queue")
                eventOccurred(false)
                return
            }
            var i = 0
            for track in queue {
                if track.trackID == newTrack.trackID { break }
                i += 1
            }
            queue.remove(at: i)
            eventOccurred(true)
        })
    }
    
}
