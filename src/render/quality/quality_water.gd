class_name QualityWater
extends QualityGroup
## The water's share of a QualityProfile: the lake's FFT waves (OceanFFT).

## Points of the FFT along a side of each cascade. The compute shaders are
## built for one size (N in src/water/fft_common.glslinc); every level holds
## that size, and tests/test_quality_profile.gd checks it.
@export var fft_size := 256
## Cascades of waves, 1 to 3: the long swell, the wind sea and the ripples.
## A lighter level drops the ripples first; the last cascade it keeps takes
## the wave numbers of those it drops.
@export_range(1, 3) var cascades := 3

func read_at_start() -> Array[StringName]:
	return [&"fft_size", &"cascades"]
