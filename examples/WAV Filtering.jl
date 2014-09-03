using AudioIO

filepath = expanduser( "~/.julia/v0.3/AudioIO/examples/You Know I'm No Good.wav" )

file = AudioIO.open( filepath )

part1 = ArrayPlayer( read( file, 44100*10, Float32 ) )
part2 = ArrayPlayer( read( file, 44100*10, Float32 ) )
part3 = ArrayPlayer( read( file, 44100*10, Float32 ) )

lowpassed  = Filt( part2, 1e3 )
highpassed = Filt( part3, 1e3, response = HIGHPASS )

play( part1 )
sleep(10)

play( lowpassed )
stop( part1 )
sleep( 10 )

play( highpassed )
stop( lowpassed )
sleep( 10 )

stop( highpassed )