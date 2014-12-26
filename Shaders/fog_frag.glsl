const float noiseScale = 1. / float(%f);
const float fogHeight = float(%f);
const float fogBottom = float(%f);
const vec3 fogColor   = vec3(%f, %f, %f);
const float mapX = float(%f);
const float mapZ = float(%f);
const float fadeAltitude = float(%f);
const float opacity = float(%f);

uniform sampler2D tex0;
uniform sampler2D tex1;

uniform vec3 eyePos;
uniform mat4 viewProjectionInv;
uniform vec3 offset;
uniform vec3 sundir;
uniform vec3 suncolor;

float noise( in vec3 x )
{
	vec3 p = floor(x);
	vec3 f = fract(x);
	f = f*f*(3.0-2.0*f);
	vec2 uv = (p.xy + vec2(37.0,17.0)*p.z) + f.xy;
	vec2 rg = texture2D( tex1, (uv + 0.5)/256.0).yx;
	return mix( rg.x, rg.y, f.z );
}

const mat3 m = mat3( 0.00,  0.80,  0.60,
                    -0.80,  0.36, -0.48,
                    -0.60, -0.48,  0.64 ) * 2.02;


struct Ray {
	vec3 Origin;
	vec3 Dir;
};

struct AABB {
	vec3 Min;
	vec3 Max;
};

bool IntersectBox(Ray r, AABB aabb, out float t0, out float t1)
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
	return t0 <= t1;
}


vec4 mapClouds( in vec3 p)
{
	float factor = 1.0 - smoothstep(fadeAltitude,fogHeight,p.y);
	p += offset;
	p *= noiseScale;

	float f = noise( p );
	f += 0.25 * noise( m*p );
	//p = m*p*2.03;
	//f += 0.1250*noise( p ); p = m*p*2.01;
	//f += 0.0625*noise( p );

	f *= factor;
	return vec4(f);
}


vec4 raymarchClouds( in vec3 start, in vec3 end)
{
	float numsteps = 20.0;
	float tstep = 1./numsteps;
	vec4 sum = vec4(0.);
	float depth = clamp(sqrt(length(end - start)*0.001), 0.0, 1.0);
	float alpha = opacity * depth;// * tstep;

	for(float t=0.0; t<=1.0; t+=tstep)
	{
		vec3 pos = mix(start, end, t);
		vec4 col = mapClouds(pos);

		vec3 lightPos = sundir*10.0 + pos;
		vec4 lightCol = mapClouds(lightPos);
		float dif = clamp((col.w - lightCol.w), 0.0, 1.0 ) * 3.0;

		vec3 lin = fogColor*1.35 + suncolor*dif;
		col.rgb *= lin;

		sum += col * alpha * (1.0 - sum.a);
	}

	sum.rgb /= (0.001 + sum.w);
	return clamp(sum, 0.0, 1.0); // returned value is opacity of cloud
}

void main()
{
	float z = texture2D(tex0, gl_TexCoord[0].st).x;

	vec4 ppos;
	ppos.xyz = vec3(gl_TexCoord[0].st, z) * 2. - 1.;
	ppos.a   = 1.;

	vec4 worldPos4 = viewProjectionInv * ppos;
	vec3 worldPos  = worldPos4.xyz / worldPos4.w;

	Ray r;
	r.Origin = eyePos;
	r.Dir = worldPos - eyePos;
	AABB box;
	box.Min = vec3(1.,fogBottom,1.);
	box.Max = vec3(mapX-1,fogHeight,mapZ-1);
	float t1, t2;
	if (!IntersectBox(r, box, t1, t2)) {
		gl_FragColor = vec4(0.);
		return;
	}

	t1 = clamp(t1, 0.0, 1.0);
	t2 = clamp(t2, 0.0, 1.0);
	vec3 startPos = r.Dir * t1 + r.Origin;
	vec3 endPos   = r.Dir * t2 + r.Origin;

	vec4 res = raymarchClouds(startPos, endPos);

	vec3 rd = normalize(r.Dir);
	float sun = clamp( dot(sundir,rd), 0.0, 1.0 );
	vec3 col = fogColor - rd.y*0.2*suncolor + 0.075;
	col += 0.2*suncolor * pow( sun, 8.0 );
	col *= 0.95;
	col  = mix( col, res.xyz, res.w );
	col += 0.1*suncolor * pow( sun, 3.0 );
	gl_FragColor = vec4( col, res.w );
	gl_FragColor.rgb *= gl_FragColor.a;
}
