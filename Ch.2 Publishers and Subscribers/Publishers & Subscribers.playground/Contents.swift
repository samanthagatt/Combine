import Foundation
import Combine

var subscriptions = Set<AnyCancellable>()

let nc = NotificationCenter.default
let notifName = Notification.Name("MyNotification")
let pub = nc.publisher(for: notifName)

example(of: "Publisher") {
    let observer = nc.addObserver(forName: notifName,
                                  object: nil,
                                  queue: nil) { notif in
        print("Notification received!")
    }
    nc.post(name: notifName, object: nil)
    nc.removeObserver(observer)
}

example(of: "Subscriber") {
    // Unlimited demand. Will continue to receive as many values as pub emits
    let sub = pub.sink { _ in
        print("Notification received from a publisher!")
    }
    nc.post(name: notifName, object: nil)
    sub.cancel()
}

example(of: "Just") {
    let just = Just("Hello world!")
    _ = just.sink(receiveCompletion: { completion in
        print("Received completion", completion)
    }, receiveValue: { value in
        print("Received value", value)
    })
    _ = just.sink(receiveCompletion: { completion in
        print("Received completion (another)", completion)
    }, receiveValue: { value in
        print("Received value (another)", value)
    })
}

example(of: "assign(to:on:)") {
    class SomeObject {
        var value: String = "" {
            didSet {
                print(value)
            }
        }
    }
    let obj = SomeObject()
    let pub = ["Hello", "world"].publisher
    _ = pub.assign(to: \.value, on: obj)
}

example(of: "Custom Subscribers") {
    // Create a publisher from the range's publisher property
    let pub = (1...6).publisher
    
    // Define custom subscriber
    final class IntSubscriber: Subscriber {
        typealias Input = Int
        typealias Failure = Never
        
        func receive(subscription: Subscription) {
            // Tells publisher that it can now send over more values (but no more than 3)
            // If recieve(_ input:) returns .none :
                // Completion will not be called because only values recieved will be 1, 2, and 3
                // There are still 3 more values left
            subscription.request(.max(3))
            
            // Completion will be called with anything over .max(6)
            // regardless of if recieve(_ input:) returns .none
            // subscription.request(.unlimited)
        }
        func receive(_ input: Int) -> Subscribers.Demand {
            // Simply print out the input
            print("Recieved Value:", input)
            // Can add to recieving value limit
            // .none is equivalent to .max(0) so won't add any
            return .max(1)
        }
        func receive(completion: Subscribers.Completion<Never>) {
            print("Recieved Completion", completion)
        }
    }
    
    // `pub` needs a subscriber in order to publish anything
    let sub = IntSubscriber()
    pub.subscribe(sub)
}

example(of: "Future") {
    func futureIncrement(
        integer: Int,
        afterDelay delay: TimeInterval
    ) -> Future<Int, Never> {
        // Defines the future (and returns it because swift 5)
        // Future: A publisher that will _eventually_ produce 1 value and then finish (succeed or fail)
        Future<Int, Never> { promise in
            // Gets printed right away because Futures are executed as soon as they are created
            // Does not require a subscriber like regular publishers
            print("Original")
            DispatchQueue
                .global()
                .asyncAfter(deadline: .now() + delay) {
                    // Increments int after a delay
                    // Calls promise with success
                    promise(.success(integer + 1))
                }
        }
    }
    
    // Delayed print statements will interfere with subsequent examples
    /*
    print("Start")
    let future = futureIncrement(integer: 1, afterDelay: 3)
    future
        .sink(receiveCompletion: { completion in
            print(completion)
        }, receiveValue: { value in
            print(value) }
        ).store(in: &subscriptions)
    future
        .sink(receiveCompletion: { print("Second", $0) },
              receiveValue: { print("Second", $0) })
        .store(in: &subscriptions)
     */
}

example(of: "PassthroughSubject") {
    enum MyError: Error {
        case test
    }
    
    final class StringSubscriber: Subscriber {
        typealias Input = String
        typealias Failure = MyError
        
        func receive(subscription: Subscription) {
            subscription.request(.max(2))
        }
        func receive(_ input: String) -> Subscribers.Demand {
            print("Recieved Value:", input)
            return input == "World" ? .max(1) : .none
        }
        func receive(completion: Subscribers.Completion<MyError>) {
            print("Recieved Completion:", completion)
        }
    }
    
    let subscriber = StringSubscriber()
    
    let subject = PassthroughSubject<String, MyError>()
    subject.subscribe(subscriber)
    
    let subscription = subject
        .sink(receiveCompletion: { completion in
            print("Recieved Completion (sink):", completion)
        }) { value in
            print("Recieved Value (sink):", value)
        }
    
    // Imparative way (instead of declarative/Combine way)
    subject.send("Hello")
    subject.send("World")
    
    // Ends sink
    subscription.cancel()
    subject.send("Still there?")
    
    subject.send(completion: .failure(.test))
    // Not registered because completion was already called
    subject.send(completion: .finished)
    subject.send("How about another one?")
}

example(of: "CurrentValueSubject") {
    var subscriptions = Set<AnyCancellable>()
    // Must be initialized with initial value
    // New subscribers will either get the initial value or the most recent published immediately
    let subject = CurrentValueSubject<Int, Never>(0)
    subject
        .print("subjectSub1")
        .sink(receiveValue: { print($0, "(sink)") })
        // subscriptions is an inout parameter so the original is updated not a copy
        .store(in: &subscriptions)
    subject.send(1)
    subject.send(2)
    
    print("Value:", subject.value)
    print("Assigning value")
    subject.value = 3
    print("Value:", subject.value)
    
    subject
        .print("subjectSub2")
        .sink(receiveValue: { print($0, "(second sink)")})
        .store(in: &subscriptions)
    
    // Both subscriptions will recieve cancel instead of finished, if following line is commented out
    subject.send(completion: .finished)
}

example(of: "Dynamically adjusting demand") {
    final class IntSubscriber: Subscriber {
        typealias Input = Int
        typealias Failure = Never
        
        func receive(subscription: Subscription) {
            subscription.request(.max(2))
        }
        func receive(_ input: Int) -> Subscribers.Demand {
            print("Recieved:", input)
            
            switch input {
                case 1:
                    // Adds 2 to max
                    return .max(2)
                case 3:
                    // Adds 1 to max
                    return .max(1)
                default:
                    return .none
            }
        }
        func receive(completion: Subscribers.Completion<Never>) {
            print("Recieved completion:", completion)
        }
    }
    
    let subscriber = IntSubscriber()
    let subject = PassthroughSubject<Int, Never>()
    
    subject.subscribe(subscriber)
    
    // Uses 1 but adds 2 (3 left)
    subject.send(1)
    // Uses 2 (2 left)
    subject.send(2)
    // Uses 1 but adds 1 (2 left)
    subject.send(3)
    // Uses 1 (1 left)
    subject.send(4)
    // Uses 1 (0 left)
    subject.send(5)
    // Max reached -- recieve(_ input:) won't be called on subscriber
    subject.send(6)
}

example(of: "Type erasure") {
    let subject = PassthroughSubject<Int, Never>()
    // Creates a type erased publisher
    let publisher = subject.eraseToAnyPublisher()
    publisher
        .sink(receiveValue: { print($0, "(sink)") })
        .store(in: &subscriptions)
    subject.send(0)
    // No send func on AnyPublisher
    // publisher.send(0)
}

/// Copyright (c) 2019 Razeware LLC
///
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
///
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
///
/// Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
/// distribute, sublicense, create a derivative work, and/or sell copies of the
/// Software in any work that is designed, intended, or marketed for pedagogical or
/// instructional purposes related to programming, coding, application development,
/// or information technology.  Permission for such use, copying, modification,
/// merger, publication, distribution, sublicensing, creation of derivative works,
/// or sale is expressly withheld.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.
