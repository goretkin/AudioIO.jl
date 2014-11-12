using AudioIO

b = AudioIO.AudioSample[]
resize!(b,80000);
b[:] = 0;

#make a node that stores samples into array
rec = ArrayRecorderNode(b)

play(rec) 

info("recording")
wait(rec)

info("playback")
play(b)