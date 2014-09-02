reload( expanduser( "~/.julia/v0.3/AudioIO/src/AudioIO.jl" ) )
import AudioIO


# Give PortAudio time to load
AudioIO.play([0])
AudioIO.sleep(2)

tones = AudioIO.SinOsc(440) + AudioIO.SinOsc( 7040 )


println( "Playing both tones")
AudioIO.play( tones )
AudioIO.sleep( 2 )
AudioIO.stop( tones )

# Sleep to check for transition
AudioIO.sleep( 0.5 )

# seem to have to redefine tones to get the filtering to work after previously playing the unfiltered tones
tones     = AudioIO.SinOsc( 440 ) + AudioIO.SinOsc( 7040 )
lowpassed = AudioIO.Filt( tones, 4e3 )

println( "Playing lowpass filterned tones" )
AudioIO.play( lowpassed )
AudioIO.sleep( 4 )
AudioIO.stop( lowpassed )

# Sleep to check for transition
AudioIO.sleep( 0.5 )

tones      = AudioIO.SinOsc( 440 ) + AudioIO.SinOsc( 7040 )
highpassed = AudioIO.Filt( tones, 4e3, response = HIGHPASS )

println( "Playing highpass filterned tones" )
AudioIO.play( highpassed )
AudioIO.sleep( 4 )
AudioIO.stop( highpassed )