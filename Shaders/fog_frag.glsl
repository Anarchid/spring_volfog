const float noiseScale = 1. / float(%f);
const float fogHeight = float(%f);
const float fogBottom = float(%f);
const float fogThicknessInv = 1. / (fogHeight - fogBottom);
const vec3 fogColor   = vec3(%f, %f, %f);
const float mapX = float(%f);
const float mapZ = float(%f);
const float fadeAltitude = float(%f);
const float opacity = float(%f);

const float sunPenetrationDepth = float(80.0); //FIXME make configurable
const float sunDiffuseStrength = float(6.0);
uniform sampler2D tex0;
uniform sampler2D tex1;

uniform vec3 eyePos;
uniform mat4 viewProjectionInv;
uniform vec3 offset;
uniform vec3 sundir;
uniform vec3 suncolor;
uniform float time;

/*const*/ float sunSpecularColor = suncolor; //FIXME
const float sunSpecularExponent = float(100.0);

float noise(in vec3 x)
{
	vec3 p = floor(x);
	vec3 f = fract(x);
	f = f*f*(3.0-2.0*f);
	vec2 uv = (p.xy + vec2(37.0,17.0)*p.z) + f.xy;
	vec2 rg = texture2D( tex1, (uv + 0.5)/256.0).yx;
	return mix( rg.x, rg.y, f.z );
}


struct Ray {
	vec3 Origin;
	vec3 Dir;
};

struct AABB {
	vec3 Min;
	vec3 Max;
};

bool IntersectBox(in Ray r, in AABB aabb, out float t0, out float t1)
{
	vec3 invR = 1.0 / r.Dir;
	vec3 tbot = invR * (aabb.Min - r.Origin);
	vec3 ttop = invR * (aabb.Max - r.Origin);
	vec3 tmin = min(ttop, tbot);
	vec3 tmax = max(ttop, tbot);
	vec2 t = max(tmin.xx, tmin.yz);
	t0 = max(t.x, t.y);
	t  = min(tmax.xx, tmax.yz);
	t1 = min(t.x, t.y);
	//return (t0 <= t1) && (t1 >= 0.);
	return (abs(t0) <= t1);
}


const mat3 m = mat3( 0.00,  0.80,  0.60,
                    -0.80,  0.36, -0.48,
                    -0.60, -0.48,  0.64 ) * 2.02;

float MapClouds(in vec3 p)
{
	p += offset;
	p *= noiseScale;
	p += time * 0.07;

	float f = noise( p );
	p = m*p - time * 0.3;
	f += 0.25 * noise( p );
	p = m*p - time * 0.07;
	f += 0.1250 * noise( p );
	p = m*p + time * 0.8;
	f += 0.0625 * noise( p );

	return f;
}


vec4 RaymarchClouds(in vec3 start, in vec3 end)
{
	float l = length(end - start);
	const float numsteps = 20.0;
	const float tstep = 1. / numsteps;
	float depth = min(l * fogThicknessInv, 1.5);

	float fogContrib = 0.;
	float sunContrib = 0.;
	float alpha = 0.;

	for (float t=0.0; t<=1.0; t+=tstep) {
		vec3  pos = mix(start, end, t);
		float fog = MapClouds(pos);
		fogContrib += fog;

		vec3  lightPos = sundir * sunPenetrationDepth + pos;
		float lightFog = MapClouds(lightPos);
		float sunVisibility = clamp((fog - lightFog), 0.0, 1.0 ) * sunDiffuseStrength;
		sunContrib += sunVisibility;

		float b = smoothstep(1.0, 0.7, abs((t - 0.5) * 2.0));
		alpha += b;
	}

	fogContrib *= tstep;
	sunContrib *= tstep;
	alpha      *= tstep * opacity * depth;

	vec3 ndir = (end - start) / l;
	float sun = pow( clamp( dot(sundir, ndir), 0.0, 1.0 ), sunSpecularExponent );
	sunContrib += sun * clamp(1. - fogContrib * alpha, 0.2, 1.) * 1.0;

	vec4 col;
	col.rgb = (fogColor + sunContrib) * suncolor;
	col.a   = fogContrib * alpha;
	return col;
}


vec3 GetWorldPos(in vec2 screenpos)
{
	float z = texture2D(tex0, screenpos).x;
	vec4 ppos;
	ppos.xyz = vec3(screenpos, z) * 2. - 1.;
	ppos.a   = 1.;
	vec4 worldPos4 = viewProjectionInv * ppos;
	worldPos4.xyz /= worldPos4.w;
	return worldPos4.xyz;
}


void main()
{
	// reconstruct worldpos from depthbuffer
	vec3 worldPos = GetWorldPos(gl_TexCoord[0].st);

	// clamp ray in boundary box
	Ray r;
	r.Origin = eyePos;
	r.Dir = worldPos - eyePos;
	AABB box;
	box.Min = vec3(0.,fogBottom,0.);
	box.Max = vec3(mapX,fogHeight,mapZ);
	float t1, t2;
	if (!IntersectBox(r, box, t1, t2)) {
		gl_FragColor = vec4(0.);
		return;
	}
	t1 = clamp(t1, 0.0, 1.0);
	t2 = clamp(t2, 0.0, 1.0);
	vec3 startPos = r.Dir * t1 + r.Origin;
	vec3 endPos   = r.Dir * t2 + r.Origin;

	// finally raymarch the volume
	gl_FragColor = RaymarchClouds(startPos, endPos);
}
