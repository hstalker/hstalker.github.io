---
title: "Efficient Hourglass APIs"
date: 2022-05-29
layout: post
published: true
---

Today's post will be focused mainly around wrapping C++ APIs around C APIs
around C++ APIs (it's turtles all the way down!), but many of the concepts
discussed can apply to other languages than C++, and most of the focus will be
placed on the C layer of an hourglass pattern library design, which is where
most of the most important design decisions are made.

# Table of contents

1. [What is an Hourglass API](#what)
2. [Illustrative Hourglass API libfoo](#illustrative)
  * [C API Header](#illustrative-c-header)
  * [C++ Implementation](#illustrative-cpp-impl)
  * [C++ API Wrapper Header](#illustrative-cpp-wrapper)
  * [C++ Client app_bar](#illustrative-cpp-client-appbar)
3. [What are the Benefits of an Hourglass API?](#benefits)
  * [ABI Stability](#benefits-abi-stability)
  * [Client Portability](#benefits-client-portability)
  * [Implementation Portability](#benefits-impl-portability)
  * [Implementation Hiding](#benefits-impl-hiding)
4. [Performance Concerns](#perf)
  * [Customizing Memory Allocation](#perf-memory-allocation)
  * [Reducing Memory Allocations & Controlling Memory Layout](#perf-controlling-memory)
  * [Static Libraries and LTO](#perf-static-lto)
5. [Avoiding ABI Breakage](#abi)
  * [Size & Layout Changes](#abi-struct-layout)
  * [API Argument/Return Value Changes](#abi-arg-return)
6. [Closing Thoughts](#closing)


# <a name="what">What is an Hourglass API?</a>

In the world of API implementation there is a design pattern commonly called the
"hourglass API" pattern [^1].

It is named an "hourglass API" because the breadth of the allowed feature-set of
the implementation medium follows an hourglass shape:

 * A wide & broad implementation medium at the bottom-most layer (often a
   feature-full systems language such as modern C, C++, or Rust -- Languages
   with complex run-times and garbage collection can sometimes be used, but this
   is much less common).
 * A thin and restricted implementation medium in the middle (commonly C,
   specifically C89 -- the ideal is an implementation with a stable ABI, and
   simple bindings access to client languages).
 * Again a wide & broad implementation medium at the top-most layer (the client
   language, which could be C++, Java, even C again! Yes, there are actually
   sometimes benefits to rewrapping in C).

Even if you are still implementing your library in C, it's a naturally arising
pattern anyway -- consider how you always end up clearly delineating between
internal functions and types and those supported and defined as being stable in
the public API. While this is naturally occurring, it's often beneficial to
carry out this delineation systematically from both an implementation and a
documentation perspective, because you gain other benefits in addition to
greater transparency and clarity over what is and isn't supported (which we will
discuss later).


# <a name="illustrative">Illustrative Hourglass API libfoo</a>

Throughout this article we will build off of a simple example. In this example
we have a library named `libfoo`, and a client application named `app_bar`.
`libfoo` provides some primitives to do some work which we will not specify. If
you are already familiar with the concept, feel free to skip to the next section
of the article. A simple hourglass API design for `libfoo` may look as follows:

## <a name="illustrative-c-header">C API Header</a>

This is the middle layer:
```c
/* libfoo.h */
/* Opaque type, only used via pointer */
struct libfoo_foo;

/* Allocate memory AND construct.
 * A real implementation would have better error reporting. */
libfoo_foo* libfoo_create_foo();
/* Do baz on given foo */
void libfoo_do_baz(libfoo_foo*);
/* Deinitialize if non-null, then free memory */
void libfoo_free_foo(libfoo_foo*);
```

## <a name="illustrative-cpp-impl">C++ API Implementation</a>

This is the bottom layer:
```cpp
// foo_lib_internal.cpp
#include "libfoo.h"

namespace {

// Imagine we have some template functions etc. under the hood.

class InternalFoo
{
public:
    // Some interface
    void baz() { /* Some behavior */ }

private:
    // Some data (could be C++ containers, etc.)
};

} // anonymous namespace

extern "C"
{

// Opaque type
struct libfoo_foo
{
    InternalFoo foo;
};

libfoo_foo* libfoo_create_foo()
{
    libfoo_foo* f{static_cast<libfoo*>(::malloc(sizeof(libfoo_foo)))};
    if (nullptr == f)
    {
        return nullptr;
    }
    try
    {
        // Construct the C++ object inside the allocated memory.
        // You can avoid separating allocation and construction in this case,
        // I keep them separated because we will talk about this later.
        ::new (&f->foo) InternalFoo{};
        return f;
    }
    catch (...) // We can't let exceptions cross ABI boundaries
    {
        ::free(f);
        return nullptr;
    };
}

void libfoo_do_baz(libfoo_foo* f)
{
    if (nullptr == f)
    {
        // A real implementation would error report
        return;
    }

    try
    {
        f->foo.baz();
    }
    catch (...)
    {
        // A real implementation would error report
        return;
    }
}

void libfoo_free_foo(libfoo_foo* f)
{
    if (nullptr != f)
    {
        // Destroy the C++ object
        std::destroy_at(&f->foo);
        ::free(f);
    }
}

} // extern "C"
```

## <a name="illustrative-cpp-wrapper">C++ Wrapper API Header</a>

This is the upper layer:
```cpp
// foo_lib_wrapper.hpp
class Foo {
public:
    Foo() : _foo{libfoo_create_foo()}
    {
        if (nullptr == _foo)
        {
            throw std::runtime_error{"Unable to create libfoo foo!"};
        }
    }
    ~Foo() noexcept
    {
        if (nullptr != _foo)
        {
            libfoo_free_foo(_foo);
            _foo = nullptr;
        }
    }

    // ... Ignoring copy/move for now ...

    void baz() { libfoo_do_baz(_foo); }

private:
    libfoo_foo* _foo{nullptr};
};
```

## <a name="illustrative-cpp-client-appbar">C++ Client app_bar</a>
```cpp
// app_bar.cpp
#inlude <foo_lib_wrapper.hpp>

int main(int /* argc */, char* /* argv */[])
{
    while (true)
    {
        Foo foo{};
        foo.baz();
        // Imagine there's some eventual break condition
    }

    return 0;
}
```

That was quite a bit of code. Don't worry too much about it -- it's primarily
just to illustrate the idea of an hourglass API. For the rest of the article we
will mostly ignore the upper C++ wrapper layer and the lower C++ layer, and
instead focus on the C middle layer. In other words, focusing on the thinnest
point of the hourglass as this is, in my opinion, the most restrictive and
interesting part. The middle layer also proves to be the most critical for
creating efficient APIs with stable ABIs (Application Binary Interface), with
the upper abstractive and lower implementation layers being significantly less
critical. For sake of argument, we will reintroduce `app_bar` but in a C form
directly using the C API.


# <a name="benefits">Benefits of an Hourglass API</a>

This must seem like a lot of additional code for no reason, so it is worth
considering: What exactly are the benefits of using a hourglass API pattern for
your library? There are a fair few...

## <a name="benefits-abi-stability">ABI Stability</a>

A restricted subset of C89 generally has a very stable ABI. By exposing an API
written in such a C89 subset, you gain the ability to maintain longstanding
compatibility for binary artifacts such as shared/dynamic libraries. This means
client applications can dynamically link to new or old versions with high degree
of success, which is a very useful property for doing things such as providing
transparent performance and security improvements without needing to rebuild
client applications.

Note that this stability is not automatically guaranteed. Like I said, it's only
stable as long as platform owners decide to maintain that stability (and not
make breaking changes to the platform's C ABI), and if you restrict your
interfaces to a relatively feature minimal interface. Additionally there are
other things which one needs to be careful of to avoid accidentally breaking ABI
compatibility for their library; this is discussed further in a later section.

As always ABI compatibility is as much about technical factors as it is about
social ones -- it is critical to maintain effective mechanisms to communicate
the state of compatibility to users, whether this by some kind of automated
checks, or by softer measures such as semantic versioning. Effective
communication is key.

## <a name="benefits-client-portability">Client Portability</a>

C -- and more specifically C89 -- is lingua franca of the computing world.
Almost every language has a capability to interface almost directly with C code.
Additionally, most programmers can at least understand basic C interfaces,
meaning relevant documentation has a very large audience generally. C has its
problems, but this widespread support is a major factor as to why it is still in
such heavy use in interfaces everywhere. The key implication of this ubiquity is
that it means that by providing a C API at all, almost every language out there
immediately gains access to your library's functionality. It may not be
convenient, but access is crucial. That access allows every client platform to
gain access to a similar if not identical feature-set for "free". How much of a
boon this is simply cannot be overstated. It is no mistake that some of the
oldest and most widely used software libraries provide C APIs; it's not just
because the implementation language happens to be C, and nowadays it is
increasingly the case that it isn't.

## <a name="benefits-impl-portability">Implementation Portability</a>

Firewalling your implementation away from client applications by providing a C
API as the fundamental public interface means that the implementation can really
use any language-platform. Your library could be implemented in C, Rust, C++,
Go, and many, many more. Even more crucial is that this gives you implementation
portability: As long as you maintain behavioral and C API compatibility, you are
able to seamlessly switch between implementation technologies under the hood.

As an example, consider you are using `libfoo`, and for one platform you target
there is no supported C++ toolchain. It is totally feasible to write an
implementation conforming to the same interface for this platform using its own
custom toolchain and/or language-platform. Conversely, if a new
language-platform comes along that offers a better implementation experience
(for instance, migrating from C implementation to a Rust implementation for
security purposes), then this can be done without necessarily breaking existing
client applications and their usage models.

## <a name="benefits-impl-hiding">Implementation Hiding</a>

We mentioned earlier that the C API serves as a "firewall" between the client
layer and the implementation layer. This can really be referred to as
implementation hiding. This can serve other purposes than simple implementation
portability as well, and can in fact be good reason to systematically follow
this pattern even if C is the only language used throughout the entire
hourglass.

One such purpose is deliberate implementation hiding in order hide proprietary
information. For example, imagine you have a library for interfacing with a
custom piece of hardware (e.g. a driver of some kind). By wrapping this with a
separate public C API, you retain the ability to hide how to interface with this
proprietary technology from public consumption. Obviously this won't prevent
people from reverse-engineering any proprietary binaries, but that's another
topic for another day.


# <a name="perf">Performance Concerns</a>

Using the hourglass pattern naively can lead to some additional overheads we
might not initially expect. In order to illustrate this, let us look at a simple
alternative `app_bar` implementation directly calling the C API:
```cpp
// app_bar.c
#inlude <foo_lib.h>

int main(int, char*[])
{
    while (true)
    {
        libfoo_foo* f = libfoo_create_foo();
        libfoo_do_baz(f);
        libfoo_free_foo(f);
    }
}
```

The first thing you may notice based on the prior implementation model, is that
in order to maintain an ABI firewall, we have had to make `libfoo_foo` be an
opaque data-type. As a result of this, allocation decisions are left up to the
implementation layer. This is often fine for simple use-cases, but consider the
case of `libfoo` being a very low-level library intended for performance
use-cases. By leaving allocation decisions up to the implementation, we make it
difficult for client applications to tailor their memory usage for their needs,
and to take advantage of optimally performing patterns.

## <a name="perf-memory-allocation">Customizing Memory Allocation</a>

The first memory allocation we will look at is the ability to support custom
allocators. By leaving allocation decisions entirely up to the implementation,
we disallow deviating from the implementers' decision. If the implementer
decided to use `malloc` and `free`, then we have no choice to but to rely on the
system allocator (or any library-based replacement `malloc` implementation we so
choose).

The obvious solution to this is to add some customization hook point. A common
technique for this often seen in small libraries such as the `stb_` family of
C micro-libraries is via a function pointer table:

```c
struct libfoo_allocator
{
    void*(*malloc)(unsigned long /* size */);
    void(*free)(void* /* ptr */);
};
/* A global allocator table used by the library for allocating memory.
 * Default to malloc/free */
static libfoo_allocator libfoo_allocator_table = {&malloc, &free};
```

If the user wants to make the library use a custom allocator, they simply change
the relevant function pointers at run-time. The library will then delegate to
this table for all allocations/deallocations.

Clearly, in this example case we are using a global table which may not always
be suitable. Different data might be best allocated with different mechanisms.
We could fix this by simply passing a table explicitly to all potentially
allocating `libfoo` routines.

There are performance implications to this, as now every allocation/deallocation
occurs via an additional indirection. Most of the time this is a low-priority
issue as the overhead of allocation/deallocation will exceed the indirection
cost, but as you optimize the allocation/deallocation routines, this overhead
becomes more and more significant.

## <a name="perf-controlling-memory">Reducing Memory Allocations & Controlling Memory Layout</a>

Another alternative approach that works around the mentioned issues with the
function pointer table approach described above is to break up the API, and
reduce the responsibilities of individual API calls. Your C API should be
fine-grained enough such that whenever it needs. You can remedy the additional
complexity by offering a higher-level API that combines these lower-level,
advanced API calls and uses sensible defaults for things like allocation. If the
client needs control, they can choose to drop to the advanced layer where
needed. This brings you away from fancy C function pointer tricks, and back
towards general classic API design principles [^2]. Additionally, because you
aren't using function pointers, you avoid additional indirections. Even better
is that the function pointer table trick can also be used in conjunction with
this approach if needed (e.g. for the simple API layered atop the advanced API).

As an example of what I mean, imagine I wanted to design an API allowing full
memory control, where a client could write the earlier described C `app_bar`
routine, but reuse the same memory. One could do so with the following:
```c
// app_bar.c
#inlude <foo_lib.h>

int main(int, char*[])
{
    void* f = malloc(libfoo_size_foo()); /* Only a single allocation! */
    /* Assume allocation always succeeds here */
    while (true)
    {
        libfoo_foo* f = libfoo_construct_foo(f_memory);
        libfoo_do_baz(f);
        libfoo_destroy_foo(f);
    }
    free(f_memory);
}
/* The simple higher level API described earlier can /also/ be provided! */
```

Imagine if we then knew we were going to have `N` different `foo`s, they
would be accessed in a linear fashion, and we wanted to get optimal performance.
With this advanced, more fundamental API we are able to do this with ease:
```c
// app_bar.c
#inlude <foo_lib.h>

int main(int, char*[])
{
#define N 20
    long foo_size = libfoo_size_foo();
    char* foos = malloc(N * foo_size); /* Only a single allocation! */
    /* Assume allocation always succeeds here */
    /* Construct all our foos */
    for (int i = 0; i < N; ++i)
    {
        libfoo_construct_foo(f_memory);
    }
    while (true)
    {
        /* Use all our foos in efficient memory access order in hot loop */
        for (int i = 0; i < N; ++i)
        {
            libfoo_do_baz(foos[i * foo_size]);
        }
    }
    /* Cleanup all our foos */
    for (int i = 0; i < N; ++i)
    {
        libfoo_destroy_foo(fs[i * foo_size]);
    }
    free(foos);
}
```

Now this example is quite hairy, and loses some type-safety, but one can imagine
how a higher-level C++ wrapper layer or something similar could take advantage
of this more fundamental, advanced API to achieve extremely high performance and
ease-of-use at the same time.

This is my personally preferred approach to achieving control, and more closely
resembles how I would design a C API in *any* context, not just for hourglass
APIs.

In my eyes, the basic rules-of-thumb are:

 * Provide multiple layers of complexity/control in your APIs.
 * Always let the user provide resources themselves where possible.
 * Keep your individual API calls simple.

## <a name="perf-static-lto">Static Libraries and LTO</a>

There is some level of overhead implied by the firewalling of the client layer
from the implementation layer via the stable middle C API layer. This is because
the compiler has little capability to gain visibility across the function call.
This is by design, and is largely what, when combined with dynamic linking,
gives access to the ABI stability guarantees we have discussed thus far.

This is something I have little experience experimenting with, but it seems to
me that, provided your library is open-source and/or provides static libraries,
it should be entirely feasible to trade-off ABI stability & largely remove the
overhead of the additional C middle API layer by taking advantage of modern
advances of LTO (Link-Time Optimization) [^3] provided by modern compiler
toolchains in order to get access to cross-module optimizations such as
inlining. This means we could design our API in an hourglass fashion, but still
allow some clients to choose to consume the exact same API without the
additional implied overhead of inter-module C function calls simply by changing
some compiler flags when building their client application. I would have to
carry out some experimentation to see how effective this is in practice.


# <a name="abi">Avoiding ABI Breakage</a>

When designing an hourglass API -- and indeed a C API in general -- if you want
to achieve some level of ABI stability, then you need to be extremely careful
about what changes you make, and what language features you take advantage of.
This is a very thorny topic, and probably deserves an article in and of itself,
so instead we will focus on a few core gotchas to be aware of when you want to
achieve ABI stability.

## <a name="abi-struct-layout">Struct Size & Layout Changes</a>

Much of the interfacing between the client layer and the C API firewall layer
involves passing around opaque data. This data needs to have some level of
stability in order to meaningfully offer ABI guarantees across versions of the
library. This means that the specific mechanism by which you design your APIs,
and the changes you make in implementation can have an impact on whether
stability is maintained.

If the size of the data-types are visible to the client, even if opaque, it is
entirely within the realm of possibility that adding new fields to these
data-types (or their constituent members recursively) can cause significant
breakage. A common workaround for this is to preemptively add unused fields of
sufficient size to the data-types, such that new data can be added without
breaking client code. For example:
```c
/* Assume packed */
struct A
{
    int x;
    /* These 16 bytes are now free to be replaced with real data */
    char unused1[16];
    int y;
};
```

An alternative workaround is to make the data-types opaque, and instead make the
the size a run-time value retrieved from the API. This is a technique we used
earlier in the performance section in order to achieve full memory layout
control on the client-side without exposing the internal structure of the
data-types.

If the layout of the data-types are visible to the client (i.e. non-opaque), it
is a breaking change to re-order data-members. This is because any code that
attempted to access the data-members based on the internal order will no longer
be touching correct offsets. Sufficiently firewalled, opaque data-types don't
suffer from this limitation, as the only code accessing data members is the
library itself, which should inherently be compatible. Fortunately there usually
isn't much reason to reorder data members between library versions, however it
is worth taking into account that details of how the implementation language
(such as C++) organizes data could potentially cause issues here at some deeper
member of the relevant data-type provided insufficient implemetation/API
firewalling.

It is worth noting, that these ABI guarantees are not provided should the client
library go out of their way to invasively access the contents of any passed
around library data (e.g. serialize a struct for access in a later run against a
new library).


## <a name="abi-arg-return">API Argument/Return Value Changes</a>

The most obvious ABI breaking change is if you add/remove API functions or
data-types, or alternatively change parameter lists or return types. I shouldn't
have to explain why making the client application attempt to call a function
with the wrong arguments will break client applications. This can cause rather
fantastical behavior.

Perhaps less obvious is one of run-time values. For instance, imagine we have a
function which returns an error result value. Altering the potential list of
return values can break expectations of the client applications, causing them to
enter an unexpected state if insufficiently defensively written. As an example,
going from:
```c
#define LIBFOO_SUCCESS 0
#define LIBFOO_NO_MEM 1

typedef unsigned int libfoo_result;

/* Can return SUCCESS or NO_MEM */
libfoo_result libfoo_do_xyz();
```
to:
```c
#define LIBFOO_SUCCESS 0
#define LIBFOO_NO_MEM 1
#define LIBFOO_RESOURCE_LOCKED 2

typedef unsigned int libfoo_result;

/* Can return SUCCESS or NO_MEM or RESOURCE_LOCKED */
libfoo_result libfoo_do_xyz();
```

is a breaking change, as the set of return values has changed. As a result any
code which operated assuming only the prior two return values were possible, can
be irreconcilably broken.

By extension, behavioral changes in general can, while remaining ABI conserving,
still be client breaking. For example, if an application assumes a certain
behavior from the library, but a new version of the library no longer performs
in the same way, it is entirely possible that the clients will no longer be
well-behaved. This is much more challenging to avoid that pretty much every
other type of breakage in a library due to Hyrum's law [^4].


# <a name="closing">Closing Thoughts</a>

All-in-all, the hourglass makes a fantastic addition to your library design
toolbox. It's not always worth the additional overhead of code to use, but when
you need it, there are many design decisions that need to be made in order to
maintain efficiency whilst also maintaining ABI stability, and these decisions
can have profound effects on the way the API is designed and structured.
Hopefully this article has served to clarify questions, and introduce new
questions.

Until next time!


[^1]: See [CppCon 2014: Hourglass APIs for C++ - Stefanus DuToit](https://www.youtube.com/watch?v=PVYdHDm0q6Y) for a more in-depth coverage of the concept.

[^2]: See [Designing and Evaluating Reusable Components - Casey Muratori (2005)](https://caseymuratori.com/blog_0024).

[^3]: See [LLVM LTO](https://llvm.org/docs/LinkTimeOptimization.html).

[^4]: See [Hyrum's Law])(https://www.hyrumslaw.com/).
