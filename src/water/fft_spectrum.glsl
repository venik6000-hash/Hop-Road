#[compute]
#version 450
// Initial amplitudes h0(k) and conj(h0(-k)) for one cascade: a fetch-limited
// JONSWAP wind sea with Donelan-Banner spreading, an optional long swell, and
// TMA shallow-water attenuation. Amplitudes change smoothly with the weather;
// the random phases never do, so presets blend without the sea jumping.
#include "fft_common.glslinc"

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;
layout(rgba32f, set = 0, binding = 0) uniform restrict writeonly image2DArray h0_out;

layout(push_constant, std430) uniform Params {
	float tile;          // cascade tile size, m
	float k_low;         // band of wavenumbers this cascade owns
	float k_high;
	float wind_speed;    // m/s at 10 m
	float fetch;         // m
	float wind_angle;    // radians, direction the waves travel
	float spread_blend;  // 0 = Donelan-Banner, 1 = isotropic
	float swell;         // 0..1 extra long-period swell
	float depth;         // m, TMA attenuation
	float gamma;         // JONSWAP peak enhancement
	float short_fade;    // m, damps capillary noise
	float amplitude;     // overall scale
	uint cascade;
	float gravity;
	float swell_angle;
	float pad;
} p;

float dispersion(float k) {
	return sqrt(p.gravity * k * tanh(min(k * p.depth, 20.0)));
}

float dispersion_derivative(float k) {
	float kh = min(k * p.depth, 20.0);
	float th = tanh(kh);
	float ch = cosh(kh);
	return p.gravity * (th + kh / (ch * ch)) / (2.0 * dispersion(k));
}

float jonswap(float omega, float wind, float fetch) {
	float g = p.gravity;
	float alpha = 0.076 * pow(wind * wind / (fetch * g), 0.22);
	float omega_p = 22.0 * pow(g * g / (wind * fetch), 1.0 / 3.0);
	float sigma = omega <= omega_p ? 0.07 : 0.09;
	float r = exp(-(omega - omega_p) * (omega - omega_p) / (2.0 * sigma * sigma * omega_p * omega_p));
	return alpha * g * g / pow(omega, 5.0) * exp(-1.25 * pow(omega_p / omega, 4.0)) * pow(p.gamma, r);
}

float peak_frequency(float wind, float fetch) {
	return 22.0 * pow(p.gravity * p.gravity / (wind * fetch), 1.0 / 3.0);
}

// Kitaigorodskii depth attenuation (TMA spectrum).
float tma(float omega) {
	float omega_h = omega * sqrt(p.depth / p.gravity);
	if (omega_h <= 1.0) {
		return 0.5 * omega_h * omega_h;
	}
	if (omega_h < 2.0) {
		return 1.0 - 0.5 * (2.0 - omega_h) * (2.0 - omega_h);
	}
	return 1.0;
}

float sech2(float x) {
	float c = cosh(clamp(x, -30.0, 30.0));
	return 1.0 / (c * c);
}

float donelan_banner(float theta, float omega, float omega_p) {
	float ratio = omega / omega_p;
	float beta;
	if (ratio < 0.95) {
		beta = 2.61 * pow(ratio, 1.3);
	} else if (ratio < 1.6) {
		beta = 2.28 * pow(ratio, -1.3);
	} else {
		float epsilon = -0.4 + 0.8393 * exp(-0.567 * log(ratio * ratio));
		beta = pow(10.0, epsilon);
	}
	return beta / (2.0 * tanh(beta * PI)) * sech2(beta * theta);
}

float wrap_angle(float a) {
	return mod(a + PI, TAU) - PI;
}

float spectrum(vec2 k) {
	float kl = length(k);
	if (kl < p.k_low || kl >= p.k_high || kl < 1e-5) {
		return 0.0;
	}
	float omega = dispersion(kl);
	float theta = wrap_angle(atan(k.y, k.x) - p.wind_angle);
	float wind = max(p.wind_speed, 0.3);
	float omega_p = peak_frequency(wind, p.fetch);
	float spread = mix(donelan_banner(theta, omega, omega_p), 1.0 / TAU, p.spread_blend);
	float s = jonswap(omega, wind, p.fetch) * spread;
	if (p.swell > 0.0) {
		// Old sea from a distant storm: long, narrow, nearly uni-directional.
		float swell_fetch = 250000.0;
		float swell_wind = max(wind * 1.1, 9.0);
		float swell_theta = wrap_angle(atan(k.y, k.x) - p.swell_angle);
		float narrow = pow(max(cos(swell_theta * 0.5), 0.0), 36.0) * 3.4;
		s += p.swell * jonswap(omega, swell_wind, swell_fetch) * narrow * 0.6;
	}
	s *= tma(omega) * exp(-kl * kl * p.short_fade * p.short_fade);
	// S(k) = S(w, theta) dw/dk / k, per wavenumber cell of area dk^2.
	float dk = TAU / p.tile;
	return s * dispersion_derivative(kl) / kl * dk * dk;
}

uint hash(uint x) {
	x ^= x >> 16u;
	x *= 0x7feb352du;
	x ^= x >> 15u;
	x *= 0x846ca68bu;
	x ^= x >> 16u;
	return x;
}

vec2 gaussian(uvec2 id, uint cascade) {
	uint seed = hash(id.x + hash(id.y + hash(cascade * 7919u + 17u)));
	float u1 = max(float(hash(seed)) / 4294967295.0, 1e-7);
	float u2 = float(hash(seed ^ 0x9e3779b9u)) / 4294967295.0;
	float r = sqrt(-2.0 * log(u1));
	return vec2(r * cos(TAU * u2), r * sin(TAU * u2));
}

void main() {
	uvec2 id = gl_GlobalInvocationID.xy;
	if (id.x >= N || id.y >= N) {
		return;
	}
	vec2 k = wave_vector(id, p.tile);
	uvec2 mirror = uvec2((N - id.x) % N, (N - id.y) % N);
	vec2 h0 = gaussian(id, p.cascade) * sqrt(spectrum(k) * 0.5) * p.amplitude;
	vec2 h0_minus = gaussian(mirror, p.cascade) * sqrt(spectrum(-k) * 0.5) * p.amplitude;
	imageStore(h0_out, ivec3(id, p.cascade), vec4(h0, cconj(h0_minus)));
}
