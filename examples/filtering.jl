reload( "/Users/jaykickliter/.julia/v0.3/AudioIO/src/AudioIO.jl" )
import AudioIO


# Give PortAudio time to load
AudioIO.play([0])
AudioIO.sleep(2)

tones        = AudioIO.SinOsc(440) + AudioIO.SinOsc(8000)
filterdTones = AudioIO.Filt( tones, 5000 )

# Now play the filtered audio
AudioIO.play( filterdTones )
AudioIO.sleep( 1 )
AudioIO.stop( filterdTones )

# Sleep to check for transition
AudioIO.sleep( 0.25 )

# Make sure I have it set up correctly
AudioIO.play( tones )
AudioIO.sleep( 1 )
AudioIO.stop( tones )





