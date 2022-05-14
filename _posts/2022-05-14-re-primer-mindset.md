---
title: "Reverse Engineering Primer: Mindset"
date: 2022-05-14
layout: post
---

In this post I will be offering a 1000ft high-level overview of the mentality
required to perform reverse engineering (with a focus on software/hardware, but
much of it applicable elsewhere too). I will not be heavily covering any
concrete specifics, but in future this may become a series of articles covering
common tools & tricks for specific types of RE (Reverse Engineering) work, such
as for reverse engineering file formats.


 1. [What is Reverse Engineering](#what-is-re)
 2. [Stakeholder Analysis](#stakeholder-analysis)
 3. [Applying the Scientific Method](#scientific-method)
 4. [Dynamic Analysis](#dynamic-analysis)
 5. [Static Analysis](#static-analysis)
 6. [Venture Forth](#venture-forth)

# <a name="what-is-re">What is Reverse Engineering (RE)?</a>

Reverse engineering is, at its core, the art of modeling a system's
implementation. It is understanding & verifying how the pieces fit together, and
using that understanding to achieve some further goal. It is working backwards,
from the end of time to the beginning once more to grasp, document and utilize
human intents and structure that have since been lost in application.


# <a name="stakeholder-analysis">Stakeholder Analysis</a>

The most fundamental key to reverse engineering absolutely anything in this
world is to place yourself in the shoes of the user. For any technology or
design there are multiple "users":

 * Designer
   + What background did the designer have? What prior work could they have
     built upon? What tools could they have used in the process?
   + Assuming laziness (or more politely: following the path of least resistance
     :-) ) can itself be a hint to the what & why.
 * Producer
   + In what context was the thing produced?
   + What properties are necessary to suit their needs?
 * Consumer
   + In what context is the thing used?
   + What properties are necessary to suit their needs?

Looking at the black-box from all of these perspectives can inform the decisions
you may make for exploration, the tools you will use & examine, and finally the
assumptions you will have about its inner workings. Reverse engineering is - in
part - the process of building technological empathy for stakeholders.


# <a name="scientific-method">Applying the Scientific Method</a>

Reverse engineering is fundamentally a scientific, exploratory process. The
field of science could be aptly described as the reverse engineering & modeling
of the laws of the universe through experimentation.

This is key, because it tells us that the scientific method is an ideal
mechanism by which to reverse engineer anything that exists within the universe
that can be understood; fortunately that which has been crafted by human hands
is (usually) comprehensible by human minds.

The core is one of an iterative process of:

 * **Forming a hypothesis.**
 * **Testing that hypothesis experimentally.**

Like science, it is not a process devoid of the soul. The creativity lies in
directing your search in the space of possible hypotheses, and creating
effective approaches for experimentation. Personally I find there is as much
creativity in picking apart creations as there is in constructing them to begin
with. Therein lies the joy of the work to me.

A hypothesis in reverse engineering could be as simple as: _"There is a pattern
of records in this file format"_ or _"This unknown block of disassembly is a xor
cipher implementation"_, to as complex as _"Each record has a certain header
format, and the contents are compressed with LZMA"_ and _"the key of this xor
cipher is **0xDEADBEEF**"_. As we reverse engineer, we form hypotheses and test
them experimentally, building our model of the black-box in an iterative way,
carving in further details to the sculpture of the mechanism with each verified
hypothesis, escaping its boxed form until it resembles the inner gears and
pistons. We simplify, hypothesize, verify, refine.

Experimentation can often be painstaking manual labor, but some experiments are
simply too laborious to carry out within reasonable man-power. The state space
for hypotheses is ever expansive, and we can't afford to do everything by eye
and workman's hand alone. As such, it's critical to be able to build out custom
experimentation apparatus. Like how in gathering data for particle physics we
may need a Large Hadron Collider, we often need bespoke tools to collect and
massage information, and to verify our findings. These can be as simple of tools
for automating frequency analysis for breaking xor ciphers, or it may be as
complex as producing a working substitution of an entire algorithm from an
executable. A file format parser, an archive extractor, an archiver, an
executable unpacker, a decompressor, a decryptor, a small Python script to find
the offsets of a known sequence of bytes in a file. The ability to craft these
tools, to leverage the power of the machine in unraveling a mechanism is
crucial to maintaining efficacy, and producing useful artifacts beyond simple
documentation and understanding. The best proof of understanding is prediction &
practice.


# <a name="dynamic-analysis">Dynamic Analysis</a>

Few things can be as informative as watching a live system at work. **Dynamic
analysis** is the process of _experimenting_ on a live, working system to
uncover its inner mechanisms. Dynamic analysis serves as an excellent staging
ground in which to poke & prod the working instance in order to determine the
general rules under which it moves. Nothing, after all, is informative as the
thing itself in presenting its workings - watching a creature live can unveil
its habits & thoughts in ways a post-mortem might not. This process can often
involve:

 * Replacing parts.
 * Testing different inputs.
 * Monitoring side-effects of operation.

In software this would be where we examine memory, monitor registries and
file-system access, sys-calls and what instructions execute when, packets sent
and received, or simply whether the system under RE crashes or not! This is
where we stub out instructions and see what happens, or where we generate files
that based on our understanding of their structure and see how the expected
consumer reacts. Tools are paramount to the process of dynamic analysis, as
there are vast counts of externalities and processes involved with gathering
sufficient data.

# <a name="static-analysis">Static Analysis</a>

**Static analysis** is the post-mortem of the field of reverse engineering. It
is the act of examining the thing under test when not in motion. This process
can really be described as the practice of examining frozen structures (data &
metadata).

In software, static analysis can be summed up as the analysis of structure. This
can be reverse-engineering and commenting a disassembly, or it can be examining
the metadata of files, or even attempting to intuit the structure of things from
their forms in stasis. The fundamental of static analysis in my mind, is that of
reconstructing interpretable structure. Understanding how block of code flow
together, and how file formats are built & parsed, how file-systems are
traversed and moulded.

Both static analysis & dynamic analysis are synergetic. Some hypotheses are best
confirmed (or denied!) in a static context, some are best in a dynamic one.
Understanding gained under one are portable to be built upon in the other. Due
to this, it must be impressed upon you, dear reader, that no good reverse
engineer can make do with one but not the other. Ignore the still for the moving
or vice versa at your own peril.


# <a name="venture-forth">Venture Forth</a>

I hope this has been useful for outlining - at a high-level - an approach for
thinking about the problem of reverse engineering. Of course, the contents of
this post alone aren't _quite_ enough to venture forth, but I can only hope
these words serve as a guideline from which to think. Whenever you are at a loss
scanning a seemingly endless hex dump of a file and your eyes glaze over,
jumping endlessly through obfuscated JavaScript, questioning the meaning of it
all through the haze of abstraction, think back to the fundamentals:

 * Understand the stakeholders.
 * Apply the scientific method:
   + Simpify
   + Hypothesize
   + Experimentally verify
   + Refine
 * Analyze systems in stasis.
 * Analyze systems in motion.

You can never truly go too far off the beaten track as long as you keep that in
mind. The mindset comes first, the tools & skills come alongside, developing
together to form intuition and inform practice.
