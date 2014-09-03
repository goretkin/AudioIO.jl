using AudioIO

filepath = expanduser( "~/.julia/v0.3/AudioIO/examples/You Know I'm No Good.wav" )

file = AudioIO.open( filepath )

part1 = ArrayPlayer( read( file, 44100*10, Float32 ) )
part2 = ArrayPlayer( read( file, 44100*10, Float32 ) )
part3 = ArrayPlayer( read( file, 44100*10, Float32 ) )


play( part1 )
sleep(10)
stop( part1 )

lowpassed = Filt( part2, 4e3 )
play( lowpassed )
sleep( 10 )
stop( lowpassed )

highpassed = Filt( part3, 4e3, response = HIGHPASS )
play( highpassed )
sleep( 10 )
stop( highpassed )
