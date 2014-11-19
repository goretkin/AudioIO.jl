import Multirate: FIRFilter, filt!, firdes, outputlength, FIRResponse, LOWPASS, HIGHPASS

export  Filt,
        Resample,
        FIRResponse,
        HIGHPASS,
        LOWPASS

type FilterRenderer <: AudioRenderer
    filter::FIRFilter
    buf::AudioBuf

    function FilterRenderer( filter::FIRFilter )
        new( filter, AudioSample[] )
    end

end

function FilterRenderer(cutoff::Real; transition::Real = 0.2*cutoff, samplerate = 44100, response::FIRResponse = LOWPASS )
    h      = firdes( cutoff, transition, samplerate = samplerate, response = response )
    filter = FIRFilter( h )
    FilterRenderer( filter )
end


function render( node::FilterRenderer, device_input::AudioBuf, info::DeviceInfo )
    input = device_input 

    if length( node.buf ) != outputlength( node.filter, length( input ) )
        resize!( node.buf, length( input ) )
    end

    filt!( node.buf, node.filter, input )
    return node.buf
end


typealias Filt AudioNode{FilterRenderer}

function Filt( cutoff::Real; response::FIRResponse = LOWPASS, transition::Real = 0.1*cutoff, samplerate = 44100 )
    Filt( FilterRenderer( cutoff, transition = transition, samplerate = samplerate, response = response ) )
end


typealias Resample AudioNode{FilterRenderer}

function Resample( in1::AudioNode, ratio::Rational )

    ratio == 1//1 && error( "can't resample by a factor of 1" )

    interpolation = num( ratio )
    decimation    = den( ratio )

    cutoff              = 0.4/decimation
    transitionWidth     = 0.1/decimation
    stopbandAttenuation = 50

    h      = firdes( cutoff, transitionWidth, stopbandAttenuation )
    h      = h.*interpolation
    filter = FIRFilter( h, ratio )

    Resample( FilterRenderer( in1, filter ) )
end