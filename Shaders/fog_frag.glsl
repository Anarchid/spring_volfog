const float fogAtten  = %f;
const float fogHeight = %f;
const vec3 fogColor   = vec3(%f, %f, %f);
const float mapX = float(%f);
const float mapZ = float(%f);
const float k = 100.0;
const vec3 up = vec3(0.0,1.0,0.0);
const vec4 nullVector = vec4(0.0,0.0,0.0,0.0);
const float fogMinHeight = float(%f);
const float noiseScale = 256.0;

uniform sampler2D tex0;
uniform sampler2D tex1;

uniform vec3 eyePos;
uniform vec2 unoise;
uniform mat4 viewProjectionInv;
uniform vec3 offset;
uniform vec3 sundir;
uniform vec3 suncolor;

float hash( float n )
{
    return fract(sin(n)*43758.5453123);
}

float noise( in vec3 x )
{
    vec3 p = floor(x);
    vec3 f = fract(x);
	f = f*f*(3.0-2.0*f);
	
	vec2 uv = (p.xy+vec2(37.0,17.0)*p.z) + f.xy;
	vec2 rg = texture2D( tex1, (uv+ 0.5)/256.0, -100.0 ).yx;
	return mix( rg.x, rg.y, f.z );
}

const mat3 m = mat3( 0.00,  0.80,  0.60,
                    -0.80,  0.36, -0.48,
                    -0.60, -0.48,  0.64 );
                
float inPrism(in vec3 pos){
	return 
	float(
		pos.y < fogHeight &&
		pos.y > fogMinHeight &&
		pos.z < mapZ-1.0 &&
		pos.x < mapX-1.0 &&
		pos.x > 1.0 &&
		pos.z > 1.0
	);
}

vec4 mapClouds( in vec3 p)
{
    float f;
    
    float factor = 1.0-smoothstep(fogHeight-20.0,fogHeight,p.y);
    factor = mix(0.0,factor,inPrism(p));
    //factor *= 1-pow(p.y/fogHeight,2);
    
    p += offset;
    p /= noiseScale;

    f  = noise( p ); p = m*p*2.02;
    f += 0.2500*noise( p ); p = m*p*2.03;
    f += 0.1250*noise( p ); p = m*p*2.01;
    f += 0.0625*noise( p );
    
    f = f*factor;
    
    return vec4(f,f,f,f);
}

vec3 planeIntersect(in vec3 startPos, in vec3 endPos, in vec3 planeNormal, in vec3 planeOrigin)
{
	vec3 dir = startPos-endPos;
	float distance = dot(planeNormal, planeOrigin-startPos) / dot(planeNormal,dir);
	return dir * distance + startPos;
} 

vec3 cullEndpoint(in vec3 startPos, in vec3 endPos){
		vec3 cullPos = endPos;
	
		if(cullPos.x < 0.0){
			cullPos =  planeIntersect(startPos, cullPos, vec3(1.,0.,0.), vec3(0.,0.,0.)); 
		}
		
		if(cullPos.x > mapX){
			cullPos =  planeIntersect(startPos, cullPos, vec3(1.,0.,0.), vec3(mapX,0.,0.)); 
		}
		
		if(cullPos.z < 0.0){
			cullPos = planeIntersect(startPos, cullPos, vec3(0.,0.,1.), vec3(0.,0.,0.)); 
		}
		
		if(cullPos.z > mapZ){
			cullPos = planeIntersect(startPos, cullPos, vec3(0.,0.,1.), vec3(0.,0.,mapZ)); 
		}
		
		if(cullPos.y > fogHeight){
			cullPos = planeIntersect(startPos, cullPos, vec3(0.,1.,0.), vec3(0.,fogHeight,0.)); 
		}
		
		return cullPos;
}

vec3 cullStartPoint(in vec3 startPos, in vec3 endPos){
	
		if(startPos.y > fogHeight){		
			startPos = planeIntersect(startPos, endPos, up, vec3(0.,fogHeight,0.));
		}

		if(startPos.x < 0.0){
			startPos = planeIntersect(startPos, endPos, vec3(1.,0.,0.), vec3(0.,0.,0.)); 
		}
		
		if(startPos.x > mapX){
			startPos = planeIntersect(startPos, endPos, vec3(1.,0.,0.), vec3(mapX,0.,0.)); 
		}
		
		if(startPos.z < 0.0){
			startPos = planeIntersect(startPos, endPos, vec3(0.,0.,1.), vec3(0.,0.,0.)); 
		}
		
		if(startPos.z > mapZ){
			startPos = planeIntersect(startPos, endPos, vec3(0.,0.,1.), vec3(0.,0.,mapZ)); 
		}
			
		return startPos;
}

vec4 raymarchClouds( in vec3 start, in vec3 end)
{
	vec4 sum = vec4(0.);
	
	vec3 sectPos = cullStartPoint(start, end);
	
	float depth = clamp(sqrt(length(end-sectPos)/1000.0),0.0,1.0);
	
	vec3 rd = normalize(start-end);

	for(int i=0; i<20; i++) // 64 steps maximum
	{
		if( sum.w>0.99 ) break; // short-circuit on full opacity or timeout?
		float t = float(i)/20.0;
		vec3 pos = mix(sectPos, end, t);
		vec4 col = mapClouds(pos);

		
		vec3 lightPos = 10.0*sundir+pos;
		float dif =  clamp((col.w - mapClouds(lightPos).w), 0.0, 1.0 )*3.0;

        vec3 lin = vec3(0.76,0.68,0.88)*1.35 + suncolor*dif;
		col.xyz *= lin;
		
		
		col.a *= 0.3;
		col.rgb *= col.a;

		sum = col*(1.0 - sum.a)*depth + sum;	
	}
	
	sum.xyz /= (0.001+sum.w);

	return clamp(sum, 0.0, 1.0); // returned value is opacity of cloud
}

void main(void)
{
	float z = texture2D(tex0, gl_TexCoord[0].st).x;

	vec4 ppos;
	ppos.xyz = vec3(gl_TexCoord[0].st, z) * 2. - 1.;
	ppos.a   = 1.;

	vec4 worldPos4 = viewProjectionInv * ppos;
	vec3 worldPos  = worldPos4.xyz / worldPos4.w;

	worldPos = cullEndpoint(eyePos, worldPos);
	vec4 res = raymarchClouds(eyePos,worldPos);
	
	vec3 rd = normalize(eyePos-worldPos);
	float sun = clamp( dot(normalize(sundir),rd), 0.0, 1.0 );
	vec3 col = vec3(0.6,0.71,0.75) - rd.y*0.2*suncolor + 0.15*0.5;
	col += 0.2*suncolor*pow( sun, 8.0 );
	col *= 0.95;
	col = mix( col, res.xyz, res.w );
	col += 0.1*suncolor*pow( sun, 3.0 );
    gl_FragColor = vec4( col, res.w );
}
