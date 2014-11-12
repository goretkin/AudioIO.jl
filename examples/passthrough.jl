using AudioIO

#take the absolute value of the hardware input and pass it to the output.
n = MemorylessNode(abs)
play(n)