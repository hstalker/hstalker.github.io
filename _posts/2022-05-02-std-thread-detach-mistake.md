---
title: "Using std::thread::detach() is Probably a Mistake"
date: 2022-05-02
layout: post
---

Beware: Opinions lie o'er yonder

---

C++ [std::thread](https://en.cppreference.com/w/cpp/thread/thread) objects are a
handy abstraction over OS threads. They are an extremely convenient
cross-platform tool, but once you are in the domain of concurrency, you are also
in the domain of pitfalls. One of the pitfalls around using them is that you
need to make sure you properly "finish" with the thread before the destructor is
called [^1]. There are two primary ways of doing so:

  1. [std::thread::join()](https://en.cppreference.com/w/cpp/thread/thread/join)
  2. [std::thread::detach()](https://en.cppreference.com/w/cpp/thread/thread/detach)

`join` acts as a synchronization point which establishes a
[happens](https://timsong-cpp.github.io/cppwp/n4659/thread.thread.member#4)-[before](https://timsong-cpp.github.io/cppwp/n4659/intro.multithread#intro.races-9.1)
relationship between thread termination and following lines of code. Detach on
the other hand is roughly equivalent to throwing caution to the wind and giving
up on any and all guarantees as to the state of the thread from the other thread
of execution's perspective.

From such a description, you may ask the very valid question: Why would you ever
want to detach then?... In response to that fine question, I will make a claim:
You probably don't. Virtually every instance I see of direct detach usage in
production systems is counter-productive [^2].


## Example Usage
For sake of illustration, here are some very simple example snippets of the two
calls in use on a `std::thread` with some added commentary.

No join or detach:
```cpp
{
  std::thread t1{[]() { /* Do stuff */ }};
  // ...
  // Do other stuff
  // ...
} // std::terminate is called, as t1 is never detached or joined despite t1 still being joinable when destroyed
```

If joined:
```cpp
{
  std::thread t1{[]() { /* Do stuff */ }};
  // ...
  // Do other stuff
  // ...
  if (t1.joinable())
  {
    t1.join(); // This can potentially indefinitely block if t1 never terminates.
  }
  // We have a guarantee that the thread of execution of t1 is complete.
  cleanup();
}
```

If detached:
```cpp
{
  std::thread t1{[]() { /* Do stuff */ }};
  // Do other stuff
  t1.detach();
  // ...
  // Continue working
  // ...
  // t1 will never block execution of the spawning thread as it is detached.
  cleanup(); // We can make no assumptions about what state t1 may be in.
}
```


## Why Would You Detach?

In order to better understand this stance of mine of mine, lets go over some
potential real use-cases for `detach`.


### 1. Joining is Tricky

The easiest one. Managing thread lifetimes in such a way you properly avoid
unintentional blocking behavior is actually quite tricky in complex
applications. Sometimes it's easier to just detach the thread and hope it
terminates correctly. Join is similarly easy to use, but requires the developer
to maintain the thread object somewhere in a proper fashion, and then offers the
potential for the join call to block the joining thread if the thread being
joined behaves improperly e.g. unintentionally locks, or enters some
undefined/unexpected state. In other words, detaching works as a guard against
poorly written code.

Detach offers an easy way out. One can simply detach whatever thread they spawn,
and, in a fire-and-forget approach to thread-management, carry on with their
business. The spawning thread won't ever be blocked, and `std::terminate` will
never be invoked as a result of forgetting to join somewhere.

```cpp
std::thread{[]() { /* Do stuff */ }}.detach();
// ... Carry on working
```

It should be a matter of no surprise that I feel little sympathy for this. As
software developers, it's best to avoid doing the easy-but-wrong thing for
longer than strictly necessary, and often some forethought can pay hefty
dividends, especially when you are dealing with something as error-prone as
concurrency.


You might think this is an unlikely scenario, but I have seen this
justification used before[^3].


### 2. Short-lived, Terminating Operations

This case has some overlap with case 1, but is much more reasonable.

Sometimes the overhead of correct thread management simply isn't worth the
effort, if you have extremely simple, well-defined operations that you known
up-front have little chance to misbehave but need to be done asynchronously
nonetheless.

The prerequisite here is that the operations have to be extremely small, and
typically well-defined enough that they are unlikely to grow in scope much if at
all[^4]. In cases where these don't hold, detaching is likely to end up being
not fit for purpose.

As with case 1, I think that whilst there is some value to this use-case, it's
still more indicative of using sub-optimal abstractions for your purposes than a
valid reason for detaching - effort of thread-management is better removed by
abstraction than entirely foregoing control via using detach. It is a better
justification than with case 1, but nonetheless not a great one.


### 3. Asynchronously Making Blocking/Unstable Calls

This is by far the most reasonable use-case (dare I say the only justifiable
use-case?), and can be considered yet another extension upon the prior
justifications.

When using poorly designed libraries from upstream, it can happen that the APIs
you need are inherently blocking or unstable[^5]. In cases where this simply
isn't sufficient for the asynchronicity and liveness profile of your downstream
application, you require some method of making the call without blocking the
calling thread of your application, and detach serves that purpose fairly well
whereas joining could indefinitely block the joining thread.

An example of the kind of problem I describe above:
```cpp
// Thread: Main
call_bad_c_library(); // Potentially blocking call

// ... Some time later
// May never happen if the earlier call blocks. Even if said call eventually
// terminates, we are blocked by it for some upstream-defined period of time,
// which may not be acceptable.
foo();
```

Detaching allows the developer to resolve this issue:
```cpp
// Thread: Main
std::thread stuckThread{[]() {
  // Thread: T1
  call_old_c_library(); // Potentially blocking call
}};
auto retainedThreadId{stuckThread.native_handle()};
stuckThread.detach();

// ... Some time later
// Will always happen - stuckThread will never block this thread provided the
// scheduler behaves sanely
foo();

// Handle stuck threads
if (threadStillLive(retainedThreadId)) {
  killThread(retainedThreadId); // Pseudocode for sake of argument - non-standard
}
```

You might have noticed the interesting things about this second snippet:

 * You need some way to cancel (or abandon) stuck threads. This is not provided
   as part of the standard interface of `std::thread` and its descendants.
 * You need some additional thread-safe method of detecting liveness of the
   thread.

It should be clear that a full solution to this problem-case becomes quite
complex, especially when we begin to take into account the possibility of
multiple calls to the blocking API rather than just one. Spawning threads isn't
exactly cheap either so if performance is necessary, even more complexity is
needed.

Pragmatism dictates that this solution can make sense, because it is often the
case that one is using pre-established libraries with pre-established blocking
semantics, and we have little choice to work around what is given by upstream.
However, therein lies the issue: This is something that - whilst a pragmatic
stop-gap - is better resolved by maneuvering such that a non-blocking
alternative of some variety is offered in the upstream API. This is little more
than a hack working around an _API bug_. Sometimes fixing/replacing upstream is
simply a more sensible long-term solution. As such, despite this being a
justifiable usage of detach, it's still not really something worth
_recommending_ in my eyes.


## Problems With Detach

So now that we have observed some potential use-cases what are the problems with
detaching?

 1. Detaching discards any in-built guarantees about a thread's state at any
    point in execution. This can cause horrible tear-down bugs when shared state
    is involved, and I shouldn't have to point out that _having no idea what a
    given thread is actually doing from other threads is a pretty bad state to
    be in for writing correctly operating software_.
 2. Detaching throws away the simplest way to establish basic synchronization
    between the spawning & spawned threads of execution. This is incredibly
    useful, and vastly easier to manage than messing about with other shared
    data and synchronization primitives. These may eventually be needed, but the
    longer you can avoid needing them, the less likely you are to make mistakes.
 3. Detach is usually a band-aid over some other issue, be that insufficient
    higher-level async modeling, or a poor upstream API. Robust software is not
    constructed by encouraging band-aids - not in the long-term anyway.


## What are the Alternatives?

### Build RAII Abstractions

This is exactly the kind of thing `std::jthread` was invented to solve. If
calling join is too much effort, just use an RAII wrapper that does it for you.


### Don't Use Threads, Use Tasks/Futures/Coroutines

Short-lived async operations are tasks. Short-lived async operations that
provide a result are futures/promises. Both of these can be cleanly modeled via
a coroutine language mechanism.

Many use-cases for detach are hidden under higher-level abstractions already
provided as part of C++. Directly managing threads is often overkill for these
kinds of use-cases, and as such using detach is a poor fit. An added benefit of
using better-fit models is that the problem being solved becomes easier to
manage and grok.


### Model *Cancellable* Asynchronous Operations

Many thread-based operations are in reality as cancellable ones. Indeed,
cancellation is a critical building block to building robust concurrent
software. Async operations can fail. Async operations can be interrupted. A
thread is just a thread, and there is more to async than the primitive of
threads.

If you build cancellable async abstractions, then the synchronization implied by
`join` stops being a problem, because all async operations have a lifetime, are
under control, and can be made to eventually terminate in a guarateed fashion.

Interestingly enough, `std::jthread` and friends from C++20 were also designed
to aid in this by the addition of `std::stop_token`; though I would argue it's
still insufficient as an abstraction due to the lack of ability to effectively
handle stuck threads. Don't even get me started on killing threads that become
stuck. You _don't_ want to be figuring out how different platforms' threading
libraries pull that one off...[^6]


## Conclusions

Using `std::thread::detach()` is probably a mistake. Think before you do
anything but `std::thread::join()`. In cases where you feel a need to detach, it
should generally be treated as a stop-gap measure until a better solution is
crafted. Better solutions will typically be more purpose-built higher-level
abstractions rather than directly using threads, or by fixing poor APIs at the
source.


[^1]: As an aside C++20 also provides a new type of standard thread object
    [std::jthread](https://en.cppreference.com/w/cpp/thread/jthread), which
    provides a guaranteed `join` call in the destructor among other things.

[^2]: And also harmful. I have seen it cause pretty horrific issues in tear-down
    for applications, and result in ossifying software architectures that are
    inherently broken, and very challenging to fix without dramatic
    refactoring. Detach used out of laziness is not to be trifled with.

[^3]: Thankfully it's rare.

[^4]: This is usually very challenging to judge, and can change at the drop of a
    hat.

[^5]: Imagine a vendor-provided C library that you don't have any real control
    over which does some blocking I/O, and sometimes livelocks/deadlocks.

[^6]: `pthread_cancel` and `pthread_exit` can do some real magic you [might not initially expect](https://gcc.gnu.org/legacy-ml/gcc-help/2015-08/msg00040.html)
    under the hood. Thread cancellation is a tricky beast, and things like
    cleanup handlers make it even more tricky.
