# riscv-vscript (mini-rv32ima-sq)
## *You heard of the TF2 Linux port, now get ready for the Linux TF2 port!*


**Click below for the YouTube video showing off this project.**

[![Writing a Really Tiny RISC-V Emulator](https://img.youtube.com/vi/zi6osAtyaio/0.jpg)](https://www.youtube.com/watch?v=zi6osAtyaio)

# What
riscv-vscript is a port of [mini-rv32ima](https://github.com/cnlohr/mini-rv32ima) to VScript (Squirrel3) that:
 - Implements a RISC-V rv32ima/Zifencei+Zicsr (and partial su) with CLINT and MMIO.
 - Is about 600 lines of code (including signed-ness helpers but excluding callbacks + usage)
 - (For more info see [mini-rv32ima](https://github.com/cnlohr/mini-rv32ima))
 - Absolutely not conformant or tested in any way.
 - Easily extensible to run your own risc-v code and plumb your own things.
 - Written in Squirrel3 and runs inside of Team Fortress 2.
 - Yes. You can run Linux, and sha256sum, etc all inside of Team Fortress 2 now.

By default when you execute the script, it will boot into a Linux environment.
The device tree (dtb) + system image is stored inside of riscv_data.nut inside of an array of hex bytes values.

It is functional in that it can run Linux, sha256sum, coremark etc and give accurate results.

## Speed

It is pretty slow, but that's primarily due to the Think rate being limited to 0.1s.

If you don't use Think and let it run and block the main thread, it runs pretty fast and is quite responsive/interactive -- but obviously that isn't desirable as it would hang the server :P

# Screenshots

![](/assets/image_0.png)
*please disregard the blatant lack of support for color codes*
![](/assets/image_1.png)
![](/assets/image_2.png)

## More info

This is basically just a raw port of mini-rv32ima to Squirrel3.
Rather annoying as Squirrel has no fixed/small size or unsigned types... only `>>>` for unsigned shift. (ie. non-sign-extend)
So we have to emulate all of that and all the logic for it is '*fun*'.
We map the player_say game event to map player text to the UART interface.

It supports basically everything you could ever want, but do
not consider it in any way conformant.
It can boot the Linux kernel, run coremark, run sha256sum and get
a correct results, etc.
It can even shutdown with `halt -f` and it actually shuts down
the risc-v computer and cleans up the entity responsible for
the Think function.

I was very close to giving up many times writing this code.
Luckily mini-rv32ima has a single-step register dump mode.
All of the debugging was done via enabling single-step, and a fixed elapsed_us
and diff-ing the single-step outputs to see where we diverge.

Special thanks to cnlohr for nerdsniping me with this tiny rv32 implementation
I was very surprised how understandable it was, and how little it takes
to have a rv32 implementation capable of actually being usable!

This code was all made in a tea-infused 6 hour coding session.

## Some Notes

**Due to Squirrel having no 64-bit or unsigned types...**

unsigned less than is implemented by splitting the number into two signed 16-bit components and doing the comparison that way.

mulh is emulated by treating it as a 64-bit mul in 16-bit parts.

divu is emulated in an interesting way... 

modu is treated the same as normal mod for now.
So far nothing has relied on the signed-ness semantics of this yet.
