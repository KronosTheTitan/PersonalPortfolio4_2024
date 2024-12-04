Shader "Custom/Ocean"
{
	Properties
	{
		_OceanCol("Ocean Colour", 2D) = "white" {}
		_Noise ("Noise", 2D) = "white" {}

		_SpecularSmoothness ("Specular Smoothness", Float) = 0
		_WaveNormalScale ("Wave Normal Scale", Float) = 1
		_WaveStrength ("Wave Strength", Range(0, 1)) = 1
		_WaveSpeed ("Wave Speed", Float) = 1
		[NoScaleOffset] _WaveNormalA ("Wave Normal A", 2D) = "bump" {}
		[NoScaleOffset] _WaveNormalB ("Wave Normal B", 2D) = "bump" {}

		[Header(Foam)]
		[NoScaleOffset] _FoamDistanceMap ("Foam Distance Map", 2D) = "white" {}
		_FoamDst ("Foam Dst", Range(0,1)) = 1
		_FoamSpeed ("Foam Speed", Float) = 1
		_FoamFrequency ("Foam Frequency", Float) = 1
		_FoamWidth ("Foam Width", Float) = 1
		_FoamEdgeBlend ("Foam Edge Blend", Float) = 1
		_ShoreFoamDst ("Shore Foam Dst", Range(0, 1)) = 0.1
		_FoamNoiseSpeed ("Foam Noise Speed", Float) = 1
		_FoamNoiseStrength ("Foam Noise Strength", Float) = 1
		_FoamNoiseScale ("Foam Noise Scale", Float) = 1
		_FoamColour ("Foam Colour", Color) = (1,1,1,1)
		_FoamMaskScale ("Foam Mask Scale", Float) = 1
		_FoamMaskBlend ("Foam Mask Blend", Float) = 1
		
        _Gloss ("Gloss",Range(0,1)) = 1     
	}
	SubShader
	{
		Pass
		{
			Offset 1, 1 // In a Z-fight with the terrain, the ocean should lose (see https://docs.unity3d.com/Manual/SL-Offset.html)
			Tags { "LightMode" = "ForwardBase" "Queue" = "Geometry"}
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma multi_compile_fwdbase

			#include "UnityCG.cginc"
			#include "UnityLightingCommon.cginc"
			#include "AutoLight.cginc"

			#include "Assets/Scripts/GeoMath.hlsl"
			#include "Assets/Scripts/Triplanar.hlsl"

			struct appdata
			{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
				float3 normal : NORMAL;
				float4 tangent : TANGENT;
			};

			struct v2f
			{
				float2 uv : TEXCOORD0;
				float4 pos : SV_POSITION;
				float3 normal : NORMAL;
				float3 wPos : TEXCOORD1;
				float3 tangent : TEXCOORD2;
				float3 bitangent : TEXCOORD3;
				LIGHTING_COORDS(4,5)
			};

			
			float4 _TestParams;

			float4 _Tint;
			sampler2D _OceanCol;
			float4 _OceanCol_TexelSize;

			float _SpecularSmoothness;
			float _WaveNormalScale, _WaveStrength, _WaveSpeed;
			sampler2D _WaveNormalA, _WaveNormalB, _Noise;

			// Foam
			sampler2D _FoamDistanceMap;
			float _FoamSpeed;
			float _FoamFrequency;
			float _ShoreFoamDst;
			float _FoamWidth;
			float _FoamEdgeBlend;
			float _FoamDst;
			float _FoamNoiseSpeed;
			float _FoamNoiseScale;
			float _FoamNoiseStrength;
			float4 _FoamColour;
			float _FoamMaskScale;
			float _FoamMaskBlend;

			float _Gloss;

			float3 calculateWaveNormals(float2 uv) {
	
				float waveSpeed = 0.35 * _WaveSpeed;
				float2 waveOffsetA = float2(_Time.x * waveSpeed, _Time.x * waveSpeed * 0.8);
				float2 waveOffsetB = float2(_Time.x * waveSpeed * - 0.8, _Time.x * waveSpeed * -0.5);
				float3 waveA = UnpackNormal(tex2D(_WaveNormalA, (uv * _WaveNormalScale) + waveOffsetA));
				float3 waveB = UnpackNormal(tex2D(_WaveNormalB, (uv * _WaveNormalScale) + waveOffsetB));

				float3 outputNormal = lerp(waveA,waveB,.5);
				
				return outputNormal;
			}

			// Calculate foam (rgb = colour; alpha = strength)
			float4 calculateFoam(float2 uv, float2 wPos) {
				float dstFromShore = tex2D(_FoamDistanceMap, uv);
				dstFromShore = saturate(dstFromShore / _FoamDst);

				// Foam noise, used to make foam lines a bit jaggedy
				float2 noiseOffset = float2(0.0617, 0.0314) * _FoamNoiseSpeed * _Time.x;
				float foamNoise = tex2D(_Noise,(wPos * _FoamNoiseScale) + noiseOffset).r;
				foamNoise = (foamNoise - 0.5) * _FoamNoiseStrength * dstFromShore; // increase noise strength further from the shore

				// More foam noise, this time used to fade out sections of the foam lines to break them up a bit
				float2 foamMaskOffset = float2(-0.021, 0.07) * _FoamNoiseSpeed * _Time.x;
				float foamMask = tex2D(_Noise,(wPos * _FoamMaskScale) + foamMaskOffset).r;
				float threshold = lerp(0.375, 0.55, saturate(dstFromShore)); // mask out more further from the shore
				foamMask = smoothstep(threshold, threshold + _FoamMaskBlend * 0.01, foamMask);
				
				// Create foam lines radiating from shore using sin wave
				float foamStrength = sin(dstFromShore * _FoamFrequency - _Time.y * _FoamSpeed + foamNoise);
				foamStrength = saturate(smoothstep(_FoamWidth * 0.1 + _FoamEdgeBlend * 0.1, _FoamWidth * 0.1, foamStrength+1)) * foamMask;
				// Create constant line of foam at the shore
				float foamAtShore = smoothstep(_ShoreFoamDst + 0.1, _ShoreFoamDst, dstFromShore);
				foamStrength = saturate(foamStrength + foamAtShore);

				// Fade out foam as it gets further away
				foamStrength *= 1-smoothstep(0.7, 1, dstFromShore);
				
				float3 foamColour = lerp(1, _FoamColour.rgb, dstFromShore);
				return float4(foamColour, foamStrength);
			}


			v2f vert (appdata v)
			{
				v2f o;
				o.pos = UnityObjectToClipPos(v.vertex);
				o.uv = v.uv;
				o.normal = UnityObjectToWorldNormal(v.normal);
				o.wPos =  mul(unity_ObjectToWorld, float4(v.vertex.xyz, 1));    
				o.tangent=UnityObjectToWorldDir(v.tangent.xyz);
				o.bitangent = cross(o.normal,o.tangent);
				o.bitangent *= (v.tangent.w * unity_WorldTransformParams.w);

				TRANSFER_VERTEX_TO_FRAGMENT(o);
				return o;
			}

			float4 frag (v2f i) : SV_Target
			{				
				// ---- Get ocean colour ----
				float3 color = tex2D(_OceanCol, i.uv);
				
				// ---- Calculate normals ----
				float3 normal = calculateWaveNormals(i.wPos.xz);
				float3 tangentSpaceNormal = normal;

				float3x3 mtxTangToWorld = {
					i.tangent.x, i.bitangent.x,i.normal.x,
					i.tangent.y, i.bitangent.y,i.normal.y,
					i.tangent.z, i.bitangent.z,i.normal.z
				};
    
				float3 N = mul(mtxTangToWorld,tangentSpaceNormal);
				//N = i.normal;
				float3 L = normalize(UnityWorldSpaceLightDir(i.wPos));

				float attenuation = LIGHT_ATTENUATION(i);
				
				float lambert = saturate(dot(N,L));
				float diffuseLight = (lambert * attenuation) * _LightColor0.xyz;

				float3 V = normalize(_WorldSpaceCameraPos- i.wPos);
				float3 H = normalize(L+V);
				float3 specularLight = saturate(dot(H, N)) * (lambert > 0);

				float specularExponent = exp2( _Gloss * 11 ) + 2;
				specularLight = pow( specularLight, specularExponent ) * _Gloss * attenuation;
				specularLight *= _LightColor0.xyz;

				float3 ambient = half3(unity_SHAr.w, unity_SHAg.w, unity_SHAb.w);
				
				color = diffuseLight * color + specularLight + (ambient * .1);
				
				// # Apply foam
				float4 foam = calculateFoam(i.uv, i.wPos.xz);				
				color = lerp(color, foam.rgb, foam.a);
				
				return float4(color,1);
			}
			ENDCG
		}
	}
	Fallback "VertexLit"
}
