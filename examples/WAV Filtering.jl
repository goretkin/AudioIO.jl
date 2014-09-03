using AudioIO

filepath = expanduser( "~/.julia/v0.3/AudioIO/examples/How Soon Is Now.wav" )

file = AudioIO.open( filepath )

part1 = ArrayPlayer( read( file, 44100*14, Float32 ) )
part2 = ArrayPlayer( read( file, 44100*13, Float32 ) )
part3 = ArrayPlayer( read( file, 44100*10, Float32 ) )

lowpassed  = Filt( part2, 4e3 )
highpassed = Filt( part3, 1e3, response = HIGHPASS )

play( part1 )
sleep(14)

play( lowpassed )
stop( part1 )
sleep( 13 )

play( highpassed )
stop( lowpassed )
sleep( 10 )
stop( highpassed )