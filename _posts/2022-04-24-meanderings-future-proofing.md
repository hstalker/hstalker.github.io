---
title: "Meanderings: Future Proofing"
date: 2022-04-25
layout: post
---

With this, I am starting a new series of posts I will call "meanderings". These
are basically what you would expect from the name - a brain-dump for myself more
than anything else. Don't expect any sage-like wisdom to flow from my
finger-tips. I'm sure I'll look back at these in fond reminiscence. Probably...

---

Future-proofing is a topic that often comes up when people discuss software
engineering. Those kinds of conversations can very rapidly go off into the
weeds, but I think it's worth taking a step back and considering what we
actually mean by the term.

In my mind, there are two primary methods of future-proofing:

1. Making it low cost (and feasible!) to totally replace a component. In this
   case, cost is the cost of untangling and removing the component + cost of
   building a new component.
2. Making it low cost (and feasible!) to extend a component to fit ones needs.
   In this case, cost is the cost of remolding the component to suit our
   changed purposes.

I will dub these two approaches 1 & 2 as _replace_ & _extend_ respectively.

In other words, something has been _future-proofed_ - insofar as we can achieve
such a nebulous goal - if we can either extend it to achieve some predicted (or
unpredicted) future needs, or replace it with an alternative, at low cost. We
want this property as software developers because it allows us to minimize cost
of refactoring to suit changing demands - an inevitability in any long-term
development process.

In many discussions about this, you will see people argue over which of the
_replace_ & _extend_ approaches are the most beneficial:
 * "Simple & concrete is best".
 * "Abstraction is cheap".

These are both viewpoints you may hear espoused in many venues such as the
dreaded orange site, or the blue alien site, or PRs, IRC channels and mailing
lists, or even in the lunch canteen. Often these are said as if they are
ideologically at odds. Is that really the case though? I think most good
software developers would claim it is not so if prodded. Really the valuable
observation to make is that they are _both_ perfectly valid forms of
future-proofing, and when one is making a decision about what to do, it should
likely be an active engineering decision between these two approaches as they
have relative trade-offs. As is often the case: The best choice is
context-specific. Being dogmatic is free until it isn't.

The perhaps unintuitive implication of this interpretation is that sometimes
simple, non-abstract code can be more effectively future-proofed, provided clean
separation of concerns is properly maintained, than a highly abstract component.
I say it's unintuitive, but I don't think this is a claim most developers would
be surprised by or even disagree with. Everyone has seen that one piece of code
that is so abstract it's impossible to grok at some point. Everyone has also
seen that one piece of code so cowboy and concrete that it can *only* be
replaced as well. It's difficult to argue against the idea that sometimes a well
written replaceable piece of code is easier to refactor than a poorly written
extensible piece of code.

Notice that I made a provision on _replacement_ being an effective choice. That
proviso is important, because if this kind of effective isolation isn't
achieved, then it's challenging to guarantee that the cost of decommissioning is
low enough for _replacement_ to be a more efficient choice than _extension_.
Extensibility isn't always a win if demands are wildly divergent over time.
Similarly, _replacement_ is only effective if the sum cost of deco + buiding a
replacement is cheaper than building something which can be effectively mangled
and then subsequently mangling it into a cthulhu-esque monstrosity.

It's worth mentioning that, for any software which lives long enough,
_replacement_ will inevitably become an approach that is applied to any piece of
code. Few things are truly extensible enough to outlive an eventual replacement.
The take-away here is probably that within the long-march of the software
development process _replacement_ is defacto last resort, and is of course more
flexible; this much is obvious since one is replacing a component in its
entirety.

Anyway, what I am getting at with these meanderings is that future-proofing can
be achieved in multiple ways, and the decision about which to choose should
probably be an active engineering decision rather than one dogmatically made.
Replaceability can matter as much if not more so than inherent flexibility, and
if one is not careful a simple but intertwined component can be more expensive
to replace than a complex but modular one.
