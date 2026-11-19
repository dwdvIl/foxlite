
// Includes from foxlite basic for custom shaders
#include "foxlite/inc/foxlite.glsl"
#include "foxlite/inc/material.glsl"
#include "foxlite/inc/lighting.glsl"
#include "foxlite/inc/sky.glsl"      // For worldDirection and sky reflections

#ifdef VERTEX
#include "foxlite/inc/mesh.glsl"
#include "foxlite/inc/armature.glsl"
#endif

#ifdef FORWARDPLUS_MOTION
#include "foxlite/inc/motionvectors.glsl"
#endif

//////////////////////////// VERTEX SHADER ////////////////////////////
#ifdef VERTEX

#define transformInstance(M, T) (M = M * T)
#define transformSkinned(M, S) (M = M * S)

#if defined(BILLBOARD)
mat4 transformBillboard(inout mat4 M, in mat4 viewMatrix) {
	mat4 fmodelView = viewMatrix * M;
	#ifdef BILLBOARD_KEEP_SCALE
	vec3 scale = vec3(
		length(vec3(M[0])),
		length(vec3(M[1])),
		length(vec3(M[2]))
	);
	#else
	const vec3 scale = vec3(1);
	#endif
	fmodelView[0] = vec4(scale.x, 0.0, 0.0, 0.0); // right
    fmodelView[1] = vec4(0.0, scale.y, 0.0, 0.0); // up
    fmodelView[2] = vec4(0.0, 0.0, scale.z, 0.0); // forward
	return fmodelView;
}
#elif defined(BILLBOARD_Y)
mat4 transformBillboard(inout mat4 M, in mat4 viewMatrix) {
	vec3 right    = normalize(vec3(viewMatrix[0][0], viewMatrix[1][0], viewMatrix[2][0]));
    const vec3 up = vec3(0.0, 1.0, 0.0);  // locked to world Y
    vec3 forward  = normalize(cross(right, up));
	right = normalize(cross(up, forward)); // reorthogonalize
	
	#ifdef BILLBOARD_KEEP_SCALE
	vec3 scale = vec3(
		length(vec3(M[0])),
		length(vec3(M[1])),
		length(vec3(M[2]))
	);
	#else
	const vec3 scale = vec3(1);
	#endif
	mat4 fmodelView = viewMatrix * mat4(
		vec4(right   * scale.x, 0.0),
		vec4(up      * scale.y, 0.0),
		vec4(forward * scale.z, 0.0),
		M[3]
	);
	return fmodelView;
}
#endif

#undef mainVert
void mainVert_basic(void)
{
	foxlite_TexCoordv = foxlite_TexCoord * uvScale + uvOffset;
	foxlite_Colorv = foxlite_Color * color;
	
	mat4 worldTransform = model;

	if(uInstanced) {
		#ifndef DISABLE_INSTANCE_COLOR
		foxlite_Colorv *= foxlite_InstanceColor;
		#endif
		transformInstance(worldTransform, foxlite_InstanceTransform);
	}

	if(uSkinned) transformSkinned(worldTransform, skin());

	#if defined(BILLBOARD) || defined(BILLBOARD_Y)
	mat4 fmodelView = transformBillboard(worldTransform, view);
	#else
	mat4 fmodelView = view * worldTransform;
	#endif

	// Inverting then transposing a mat4 is never good in the GPU
	// but it would take tons and tons of operations in HScript and we don't want that either
	mat4 invfmodelView = fusedInverseTranspose(fmodelView);
	
	vec4 localPosition = vec4(foxlite_Position.xyz, 1.0);
	vec4 worldPosition = worldTransform * localPosition;
	viewPosition = fmodelView * localPosition;

	modelViewNormal = normalize(basis(invfmodelView) * foxlite_Normal);

	#ifdef NORMAL_MAP
	vec3 tangentView = normalize(basis(invfmodelView) * foxlite_Tangent.xyz);
	
	// Re-orthogonalize tangent with respect to normal (Gram-Schmidt)
	// This is done because the tangent might not be perfectly perpendicular to Normal
	tangentView = normalize(tangentView - dot(tangentView, modelViewNormal) * modelViewNormal);

	// Create TBN matrix
	TBN = tbnNormalTangent(modelViewNormal, tangentView);
	TBN[1] *= foxlite_Tangent.w; // bitangent handedness
	#endif

	#ifdef SKY_REFLECTIONS
	worldDirection = viewToWorld(viewPosition);
	worldBasis = transpose(basis(invView));
	#endif

	#ifdef VERTEX_LIGHTING
	// Doesn't make much sense to calculate PBR materials here

	#ifdef FOG
	
	#ifdef FAST_FOG
	float fogStrength = -viewPosition.z;
	#else
	float fogStrength = length(viewPosition);
	#endif

	// Vertex interpolated fog
	fogStrength = clamp((fogStrength - fogStart) / (fogEnd - fogStart), 0.0, 1.0);
	#else
	const float fogStrength = 0.0;
	#endif

	float shininess = (1.0 - uRoughness) * (1.0 - uRoughness) * 256.0;
	foxlite_Colorv.rgb = light(foxlite_Colorv.rgb, -modelViewNormal, viewPosition.xyz, uSpecular, shininess);

	#ifdef FOG 
	
	#ifdef LINEAR_FOG
	foxlite_Colorv.rgb = mix(foxlite_Colorv.rgb, fogColor, fogStrength);
	#else
	foxlite_Colorv.rgb = mix(foxlite_Colorv.rgb, fogColor, fogStrength * fogStrength);
	#endif
	#endif
	
	#elif !defined(UNSHADED) && defined(SHADOW_GLSL) && !defined(SHADOW_PASS)
	setupShadows(worldPosition, modelViewNormal);
	#endif

	gl_Position = projection * viewPosition;

	/////////////////////////////// Motion vectors ///////////////////////////////

	#if defined(FORWARDPLUS_MOTION) && defined(MOTIONVECTORS_GLSL)

	mat4 prevWorldTransform = prevModel;

	if(uInstanced) transformInstance(prevWorldTransform, foxlite_PrevInstanceTransform);

	if(uSkinned) transformSkinned(prevWorldTransform, prevSkin());

	#if defined(BILLBOARD) || defined(BILLBOARD_Y)
	mat4 prevFmodelView = transformBillboard(prevWorldTransform, prevView);
	#else
	mat4 prevFmodelView = prevView * prevWorldTransform;
	#endif

	vec4 prevViewPos = prevFmodelView * localPosition;
	vec4 prevClipPos = projection * prevViewPos;

	motionCurClipPos = gl_Position;
	motionPrevClipPos = prevClipPos;
	#endif
}
#define mainVert mainVert_basic
#endif
/////////////////////////////////////////////////////////////////////////

//////////////////////////// FRAGMENT SHADER ////////////////////////////

#ifdef FRAGMENT
#undef mainFrag
void mainFrag_basic() {
	#ifndef SOLID
	
	#ifdef SCREEN_UV_AS_COORD
	vec4 albedo = texture2D(bitmap, ScreenUV);
	#else
	vec4 albedo = texture2D(bitmap, foxlite_TexCoordv);
	#endif
	albedo *= foxlite_Colorv;
	
	#if !defined(NO_ALPHA_SCISSOR) && !(defined(ALPHA_DITHER) || defined(ALPHA_DITHER_FAST))
	if(albedo.a < alphaScissor) discard; // Alpha cutout (disabled when alpha dithering is enabled)
	#endif
	#else
	vec4 albedo = foxlite_Colorv;
	#endif

	#if defined(ALPHA_DITHER) || defined(ALPHA_DITHER_FAST)
	if(alphaDither(albedo.a) < 1.0) discard;
	albedo.a = 1.0;
	#endif

	#ifdef SHADOW_PASS
	// Stop code here, we don't need any extra operations
	gl_FragData[0] = albedo;
	return;
	#endif

	vec3 normalView = modelViewNormal;

	#ifndef VERTEX_LIGHTING

	#ifdef FOG

	#ifdef FAST_FOG
	float fogStrength = -viewPosition.z;
	#else
	float fogStrength = length(viewPosition);
	#endif

	fogStrength = clamp((fogStrength - fogStart) / (fogEnd - fogStart), 0.0, 1.0);
	#else
	const float fogStrength = 0.0;
	#endif

	//if(fogStrength < 1.0) { // Fog occlusion, prevents expensive calculations on fully fog-occluded pixels.
	#ifdef NORMAL_MAP
		vec3 tangentNormal = texture2D(normalMap, foxlite_TexCoordv).xyz * 2.0 - 1.0;
		normalView = normalize(TBN * tangentNormal);
	#endif
		
	#ifdef ORM_MAP
		vec3 specular   = uSpecular;
		float roughness = uRoughness;
		float metallic  = uMetallic;

		// From the glTF 2.0 spec
		vec4 ormData = texture2D(ormMap, foxlite_TexCoordv);
		float ao   = ormData.r + step(ormData.r, 0.0);
		roughness *= ormData.g;
		metallic  *= ormData.b;
	#else
		// const uniform hack for GLES
		#define specular uSpecular
		#define roughness uRoughness
		#define metallic uMetallic
		const float ao = 1.0;
	#endif

	#ifndef UNSHADED
	float shininess = max((1.0 - roughness) * (1.0 - roughness) * 256.0, 1.0);
	albedo.rgb = light(albedo.rgb, -normalView, viewPosition.xyz, specular, shininess);
	#endif

	#ifdef SKY_REFLECTIONS
		vec3 dir = reflect(normalize(worldDirection), worldBasis * normalView);
		vec4 skyColor = panoramaSky(skyTexture, dir, pow(8.0, roughness)-1.0);
	#ifdef SKY_RADIANCE
		vec4 envColor = pow(panoramaSky(skyTexture, worldBasis * normalView, float(SKY_RADIANCE_LEVEL)), 1./vec4(4));	
		albedo *= envColor;
	#endif
		#ifdef FRESNEL
		vec3 F0 = mix(vec3(0.04), albedo.rgb, metallic);
		vec3 F = F0 + (1.0 - F0) * pow(1.0 - max(dot(normalView, -normalize(viewPosition.xyz)), 0.0), 5.0);
		vec3 kD = (1.0 - F) * (1.0 - metallic); // energy conservation
		albedo.rgb = kD * albedo.rgb + skyColor.rgb * F;
		#else
		albedo.rgb = mix(albedo.rgb, skyColor.rgb, clamp(metallic, 0.0, 1.0));
		#endif
	#else
	 	#ifdef LIGHTING_GLSL
		albedo.rgb = mix(albedo.rgb, albedo.rgb * ambientLight, clamp(metallic, 0.0, 1.0)); // Fake metalness
		#endif
	#endif
	
	//}
	#ifdef FOG
	
	#ifndef FOG_TRANSPARENCY
		// const uniform hack for GLES
		#define fogFragColor fogColor.rgb
	#else
		vec3 fogFragColor = mix(gl_LastFragData[0].rgb, fogColor.rgb, fogColor.a);
	#endif
	
	#ifdef LINEAR_FOG
		albedo.rgb = mix(albedo.rgb, fogFragColor, fogStrength);
	#else
		albedo.rgb = mix(albedo.rgb, fogFragColor, fogStrength * fogStrength);
	#endif

	#endif
	#endif

	#ifdef EMISSIVE_MAP
	vec3 emission = uEmissive * texture2D(emissiveMap, foxlite_TexCoordv).rgb;
	albedo.rgb += emission;
	#else
	#define emission uEmissive;
	albedo.rgb += uEmissive;
	#endif

	gl_FragData[0] = albedo;
	
	#ifdef FORWARDPLUS
	gl_FragData[1].xyz = normalView;
	gl_FragData[1].w = metallic;
	#endif
	#if defined(FORWARDPLUS_MOTION) && defined(MOTIONVECTORS_GLSL)
	gl_FragData[2].xyz = getMotion(motionCurClipPos, motionPrevClipPos);
	gl_FragData[2].w = roughness;
	#endif
}
#define mainFrag mainFrag_basic
#endif
/////////////////////////////////////////////////////////////////////////