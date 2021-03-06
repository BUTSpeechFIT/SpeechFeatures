#######################################################################
# Default settings

# Preprocessor
const REMOVEDC_DEFAULT          = true
const DITHERING_DEFAULT         = 0.0

# Framing
const SRATE_DEFAULT             = 16000
const FRAME_DURATION_DEFAULT    = 0.025
const FRAME_STEP_DEFAULT        = 0.01
const PREEMPHASIS_DEFAULT       = 0.97
const WINDOW_FUNCTION_DEFAULT   = HannWindow
const WINDOW_POWER_DEFAULT      = 0.85

# FBANK
const NFILTERS_DEFAULT          = 26
const LOFREQ_DEFAULT            = 80
const HIFREQ_DEFAULT            = 7600

# MFCC
const ADD_ENERGY_DEFAULT        = true
const NCEPS_DEFAULT             = 12
const LIFTERING_DEFAULT         = 22

# Deltas
const DELTA_ORDER_DEFAULT       = 2
const DELTA_WIN_DEFAULT         = 2

# Post-processing
const MEAN_NORM_DEFAULT         = true

#######################################################################

struct LogMagnitudeSpectrum
    pp::Preprocessor
    fx::FrameExtractor
    fft::FFT
end

function LogMagnitudeSpectrum(;
    removedc = REMOVEDC_DEFAULT,
    dithering = DITHERING_DEFAULT,
    srate = SRATE_DEFAULT,
    frameduration = FRAME_DURATION_DEFAULT,
    framestep = FRAME_STEP_DEFAULT,
    preemphasis = PREEMPHASIS_DEFAULT,
    windowfn = WINDOW_FUNCTION_DEFAULT,
    windowpower = WINDOW_POWER_DEFAULT
)
    pp = Preprocessor(removedc, dithering)
    fx = FrameExtractor(;srate, frameduration, framestep, preemphasis, windowfn,
                        windowpower)
    fft = FFT(siglen = Int(srate*frameduration))
    LogMagnitudeSpectrum(pp, fx, fft)
end

function (lms::LogMagnitudeSpectrum)(x::AbstractVector)
    x |> lms.pp |> lms.fx |>  lms.fft .|> abs .|> log
end

struct LogMelSpectrum{T<:AbstractMatrix}
    pp::Preprocessor
    fx::FrameExtractor
    fft::FFT
    fbank::T
end

function LogMelSpectrum(;
    removedc = REMOVEDC_DEFAULT,
    dithering = DITHERING_DEFAULT,
    srate = SRATE_DEFAULT,
    frameduration = FRAME_DURATION_DEFAULT,
    framestep = FRAME_STEP_DEFAULT,
    preemphasis = PREEMPHASIS_DEFAULT,
    windowfn = WINDOW_FUNCTION_DEFAULT,
    windowpower = WINDOW_POWER_DEFAULT,
    nfilters = NFILTERS_DEFAULT,
    lofreq = LOFREQ_DEFAULT,
    hifreq = HIFREQ_DEFAULT
)
    pp = Preprocessor(removedc, dithering)
    fx = FrameExtractor(srate, frameduration, framestep, preemphasis, windowfn,
                        windowpower)
    fft = FFT(siglen = Int(srate*frameduration))
    fbank = FilterBank(nfilters; srate, fft.fftlen, lofreq, hifreq)
    LogMelSpectrum(pp, fx, fft, fbank)
end

function (lms::LogMelSpectrum)(x::AbstractVector)
    ( lms.fbank' * (x |> lms.pp |> lms.fx |>  lms.fft .|> abs) ) .|> log
end

struct MFCC{T<:AbstractMatrix,F<:AbstractMatrix,G<:AbstractVector}
    pp::Preprocessor
    fx::FrameExtractor
    fft::FFT
    fbank::T
    dct::F
    lifter::G
    addenergy::Bool
end

function MFCC(;
    removedc = REMOVEDC_DEFAULT,
    dithering = DITHERING_DEFAULT,
    srate = SRATE_DEFAULT,
    frameduration = FRAME_DURATION_DEFAULT,
    framestep = FRAME_STEP_DEFAULT,
    preemphasis = PREEMPHASIS_DEFAULT,
    windowfn = WINDOW_FUNCTION_DEFAULT,
    windowpower = WINDOW_POWER_DEFAULT,
    nfilters = NFILTERS_DEFAULT,
    lofreq = LOFREQ_DEFAULT,
    hifreq = HIFREQ_DEFAULT,
    nceps = NCEPS_DEFAULT,
    liftering = LIFTERING_DEFAULT,
    addenergy = ADD_ENERGY_DEFAULT
)
    pp = Preprocessor(removedc, dithering)
    fx = FrameExtractor(srate, frameduration, framestep, preemphasis, windowfn,
                        windowpower)
    fft = FFT(siglen = Int(srate*frameduration))
    fbank = FilterBank(nfilters; srate, fft.fftlen, lofreq, hifreq)
    dct = dctbases(nceps, nfilters)
    lift = lifter(nceps, liftering)
    MFCC(pp, fx, fft, fbank, dct, lift, addenergy)
end

function (mfcc::MFCC)(x::AbstractVector)
    frs = x |> mfcc.pp |> mfcc.fx
    melspec = (mfcc.fbank' * (frs |>  mfcc.fft .|> abs) ) .|> log
    melceps = mfcc.dct * melspec

    # This normalization constant was used in HTK, it compresses the
    # dynamic range of the features.
    mfnorm = sqrt(2. / size(mfcc.fbank, 2))

    lift_melceps = (mfcc.lifter * mfnorm) .* melceps

    if mfcc.addenergy
        return vcat(log.(sum((frs .^2), dims = 1)), lift_melceps)
    end

    lift_melceps
end

struct DeltaCoeffs
    order::Integer
    win::Integer
end

function DeltaCoeffs(;order = DELTA_ORDER_DEFAULT, deltawin = DELTA_WIN_DEFAULT)
    DeltaCoeffs(order, deltawin)
end

function (dc::DeltaCoeffs)(X::AbstractMatrix)
    X_and_deltas = [X]
    for o in 1:dc.order
        push!(X_and_deltas, delta(X_and_deltas[end]))
    end
    vcat(X_and_deltas...)
end

struct MeanNorm end

function (::MeanNorm)(X::AbstractMatrix)
    X .- sum(X, dims = 2) ./ size(X, 2)
end

