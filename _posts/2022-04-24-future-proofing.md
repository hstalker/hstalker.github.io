---
title: "Future Proofing"
date: 2022-04-24
layout: post
---

Future-proofing is a topic that often comes up when people discuss software
engineering. Those kinds of conversations can very rapidly go off into the
weeds, but I think it's worth taking a step back and considering what we
actually mean by the term.

In my mind, there are two primary methods of future-proofing:

1. Substitutability - Making it low cost (and feasible!) to totally replace a
   component.
2. Extension - Making it low cost (and feasible!) to extend a component to fit
   ones needs.

In case 1, total cost is roughly equal to the cost of untangling and removing
the component + cost of building a new component.

In case 2, total cost is roughly equal to the cost of remolding the component to
suit our changed purposes.

To simplify things, I will dub these two approaches 1 & 2 as _replace_ &
_extend_ respectively.

In other words, something has been _future-proofed_ - insofar as we can achieve
such a nebulous goal - if we can either extend it to achieve some known or
unknown future needs, or replace it with an alternative, at reasonable cost.
This is a desirable property for our software to have as software developers,
because it allows us to minimize the cost of pivoting to suit changing
requirements; as we all know, changing demands are an inevitability of the
development process, so this is quite _pivotal_ (sorry...).

You will see people argue over which of the _replace_ & _extend_ approaches are
the most beneficial. Sometimes you may see it be rephrased as the following
stances:
 * "Concrete & simple is the best approach for refactorability".
 * "Abstract & flexible is the best approach for achieving refactorability".

The main thrust here is that "Concrete & simple" is easily substitutable, and
"abstract & flexible" is easily extensible. These tend to be portrayed as if
they are ideologically at odds, but I would dispute that is the case. The very
idea that the abstract and the concrete are at odds is, in my view, as laughable
as portraying a hammer and a chisel as at odds -- you need both to carve a
masterpiece of marble.

_Extensibility_ isn't always a win if demands are wildly divergent over time.
Similarly, _replacement_ is only effective if the sum-cost of decommissioning
and then building a replacement is cheaper than building an extensible bedrock
and extending it, however eldritch said bedrock may become.

Let us leave dogma at the kennels where it belongs and face the facts: Sometimes
well written substitutable & concrete code is easier to refactor than poorly
written extensible & abstract code, and sometimes vice-versa is true. It's
always context dependent. Not only that, but it's also dependent on the quality
of implementation regardless! Deeply entangled concrete code is no more
sufficient than wildly complex and leaky abstractions.

---

So what is future-proofing? future-proofing is all about choosing the right
tools in any situation to meet our parameters of _reasonable future cost_. Its
basis lies in our ability to predict and empower later actions. As always when
predicting the future, there is no silver bullet that will help us deal with
both a potential vampire scenario and a werewolf scenario. The heart of our
craft as software developers is our ability to see our real-world constraints
and path-find a way to the most appropriate solution using the most appropriate
tools...

... Until the business forces us to hack up an MVP we end up rolling straight
into production anyway.
