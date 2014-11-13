using AudioIO

# Give PortAudio time to load
play([0])
sleep(2)

tones = SinOsc(440) + SinOsc( 7040 )

println( "Playing both tones")
play( tones )
sleep( 2 )
stop( tones )

# Sleep to check for transition
sleep( 0.5 )

# seem to have to redefine tones to get the filtering to work after previously playing the unfiltered tones
tones     = SinOsc( 440 ) + SinOsc( 7040 )
lowpassed = Filt( tones, 4e3 )

println( "Playing lowpass filterned tones" )
play( lowpassed )
sleep( 4 )
stop( lowpassed )

# Sleep to check for transition
sleep( 0.5 )

tones      = SinOsc( 440 ) + SinOsc( 7040 )
highpassed = Filt( tones, 4e3, response = HIGHPASS )

println( "Playing highpass filterned tones" )
play( highpassed )
sleep( 4 )
stop( highpassed )