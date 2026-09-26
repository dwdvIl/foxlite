package foxlite.loaders;

import foxlite.culling.BoundingBox;
import StringTools;
import haxe.ds.StringMap;
import foxlite.FoxCache;
import foxlite.loaders.FoxLoaderUtil;
import foxlite.material.FoxMaterial;
import foxlite.renderer.FoxRenderer;
import foxlite.mesh.FoxMesh;
import openfl.geom.Vector3D;

class FoxOBJLoader {

	/**
		Loads an OBJ file along with its materials if exists.

		Note: You can assign the OBJ's meshes directly to a FoxModel and add it to the scene by doing this:
		```haxe
		var model = new FoxModel();
		model.loadOBJ("data/my model.obj");
		scene.add(model);
		```

		@param name The OBJ asset path
		@param extraShaderFlags (Optional) A String array containing additional flags you want to use for all the material shaders
		@param customShaderPath (Optional) The path to a custom shader if you need it. The default is foxlite/basic

		@returns An Object containing an Array of meshes (with materials applied) and a Map containing the materials from the MTL file (if it exists).
	**/
	public static function load(name:String, ?extraShaderFlags:Array<String>, ?customShaderPath:String):{meshes:Array<FoxMesh>, materials:Map<String, FoxMaterial>} {
		// Check cache
		if(FoxCache.meshes().exists(name)) {
			var meshes = FoxCache.meshes().get(name);
			var materials:Map<String, FoxMaterial> = new StringMap();
			for(m in meshes) {
				if(!materials.exists(m.material.name)) materials.set(m.material.name, m.material);
			}
			return {meshes:meshes, materials: materials};
		}

		var obj = FoxLoaderUtil.loadText(name);
		if(obj == null) {
			FoxLog.warning('FoxOBJLoader', 'Could not load OBJ: ${name} (Not found.)');
			return null;
		}

		// Per mesh data
		var vertices:Array<Float> = [];
		var uvtData:Array<Float> = [];
		var normals:Array<Float> = [];
		var indices:Array<Int> = [];
		var colors:Array<Float> = [];

		// Remapping buffers
		var verticesRaw:Array<Float> = [];
		var normalsRaw:Array<Float> = [];
		var uvtDataRaw:Array<Float> = [];
		var colorsRaw:Array<Float> = [];
		// OBJ files...
		var uniqueIDs:Map<String, Int> = new StringMap();

		var vertexCount:Int = 0;
		var textureCount:Int = 0;
		var normalCount:Int = 0;
		var colorCount:Int = 0;

		var vertexOffset:Int = 0;
		var textureOffset:Int = 0;
		var normalOffset:Int = 0;
		var colorOffset:Int = 0;

		var curIndex:Int = 0;

		var curMesh:FoxMesh = null;
		var __prevMesh:FoxMesh = null;
		var meshes:Array<FoxMesh> = [];
		var groupBuildStage:Int = -1;
		var bigIndices:Bool = false;

		var materials:Map<String, FoxMaterial> = new StringMap();
		var matPath:String = null; // But it's just a theory

		var minVertex:Vector3D = new Vector3D(1e7, 1e7, 1e7);
		var maxVertex:Vector3D = new Vector3D(-1e7, -1e7, -1e7);

		function finishMesh() {
			curMesh?.setArrays(vertices, uvtData, indices, null, normals, colors, null, null, bigIndices);
			if(curMesh != null) curMesh.bounds = new BoundingBox(minVertex, maxVertex);
			if(curMesh != null && curMesh.material == null) curMesh.material = FoxRenderer.MISSING_MATERIAL; // What happened to our material...
					
			curMesh = new FoxMesh();
			curMesh.assetsKey = name;
			meshes.push(curMesh);

			// Clear previous work
			vertices.resize(0); verticesRaw.resize(0);
			uvtData.resize(0); uvtDataRaw.resize(0);
			normals.resize(0); normalsRaw.resize(0);
			indices.resize(0);
			colors.resize(0); colorsRaw.resize(0);
			uniqueIDs.clear();
			curIndex = 0;
			bigIndices = false;

			minVertex.setTo(1e7, 1e7, 1e7);
			maxVertex.setTo(-1e7, -1e7, -1e7);

			vertexOffset = vertexCount;
			textureOffset = textureCount;
			normalOffset = normalCount;
			colorOffset = colorCount;
		}

		FoxLoaderUtil.forEachLine(obj, line -> {
			var data = StringTools.trim(line).split(' ');
			var op = data.shift();
			switch(op) {
				case 'mtllib': { // Load material
					matPath = name.substr(0, name.lastIndexOf('/')+1) + data.join(' ');
					materials = FoxMTLLoader.load(matPath, extraShaderFlags, customShaderPath);
				};
				case 'usemtl': { // Set material
					var material = materials?.get(data.join(' ')); // Join spaces since names can have them
					if(__prevMesh == curMesh && __prevMesh?.material != null && curMesh?.material != null) {
						FoxLog.warning('FoxOBJLoader', 'Material "${material.name}" tried to overwrite mesh material "${curMesh.material.name}". FoxLite does not support per-face materials, skipping!!');
					}
					else curMesh.material = material;
					__prevMesh = curMesh;
				};
				case 'o': { // New object
					finishMesh();
					groupBuildStage = 0;
				};
				case 'g': { // Group
					// In this case we want to process triangles until the end, then we finish the object
					if(groupBuildStage == 1) {
						groupBuildStage = 2;
					}			
				};
				case 'v': { // Vertex
					if(groupBuildStage == -1) {
						// Model builder started without a mesh!
						// We are probably loading a grouped mesh, defer build
						curMesh = new FoxMesh();
						curMesh.assetsKey = name;
						meshes.push(curMesh);
						groupBuildStage = 1;
					}
					else if(groupBuildStage == 2) {
						// We finished building faces
						finishMesh();
						groupBuildStage = 1;
					}

					verticesRaw.push(Std.parseFloat(data[0]));
					verticesRaw.push(Std.parseFloat(data[1]));
					verticesRaw.push(Std.parseFloat(data[2]));
					vertexCount += 1;

					if(data.length > 3) { // Colors
						colorsRaw.push(Std.parseFloat(data[3]));
						colorsRaw.push(Std.parseFloat(data[4]));
						colorsRaw.push(Std.parseFloat(data[5]));
						colorCount += 1;
					}
				}
				case 'vn': { // Vertex normals
					normalsRaw.push(Std.parseFloat(data[0]));
					normalsRaw.push(Std.parseFloat(data[1]));
					normalsRaw.push(Std.parseFloat(data[2]));
					normalCount += 1;
				}
				case 'vt': { // Texture coordinates
					uvtDataRaw.push(Std.parseFloat(data[0]));
					uvtDataRaw.push(1.0 - Std.parseFloat(data[1]));
					textureCount += 1;
				}
				case 'f': { // Face
					for(d in data) {
						var fmt = d.split('/');

						// Write vertices
						var idx = uniqueIDs.get(d);
						if(idx != null) {
							indices.push(idx);
							continue;
						}
						
						var f0 = Std.parseInt(fmt[0]) - 1;
						var v = (f0 - vertexOffset) * 3;

						var vx = verticesRaw[v], vy = verticesRaw[v+1], vz = verticesRaw[v+2];
						vertices.push(vx);
						vertices.push(vy);
						vertices.push(vz);

						minVertex.x = Math.min(minVertex.x, vx);
						minVertex.y = Math.min(minVertex.y, vy);
						minVertex.z = Math.min(minVertex.z, vz);

						maxVertex.x = Math.max(maxVertex.x, vx);
						maxVertex.y = Math.max(maxVertex.y, vy);
						maxVertex.z = Math.max(maxVertex.z, vz);

						if(colorCount > 0) {
							var c = (f0 - colorOffset) * 3;
							colors.push(colorsRaw[c  ]);
							colors.push(colorsRaw[c+1]);
							colors.push(colorsRaw[c+2]);
							colors.push(1);
						}
						
						if(fmt.length >= 2 && fmt[1] != '') { // _t_
							var t = (Std.parseInt(fmt[1]) - 1 - textureOffset) * 2;
							uvtData.push(uvtDataRaw[t  ]);
							uvtData.push(uvtDataRaw[t+1]);
						}
						if(fmt.length == 3) { // __n
							var n = (Std.parseInt(fmt[2]) - 1 - normalOffset) * 3;
							normals.push(normalsRaw[n  ]);
							normals.push(normalsRaw[n+1]);
							normals.push(normalsRaw[n+2]);
						}
						indices.push(curIndex);

						uniqueIDs.set(d, curIndex);
						curIndex += 1;
						if(curIndex > 65535) bigIndices = true;
					}
				}
				if(data.length == 4) { // If we're working with quads we need to triangulate
					// Quad is wound clockwise, so does our triangles
					// We create 2 additional indices:
					// 0,1,2,3 -> 0,1,2,0,2,3
					var len:Int = indices.length;
					var i3:Int = len-1;
					var v3:Int = indices[i3];

					indices[i3] = indices[len-4];
					indices.push(indices[len-2]);
					indices.push(v3);
				}
			}
		});

		// EOF reached
		// Finish pending mesh
		curMesh?.setArrays(vertices, uvtData, indices, null, normals, colors, null, null, bigIndices);
		if(curMesh != null) curMesh.bounds = new BoundingBox(minVertex, maxVertex);
		if(curMesh != null && curMesh.material == null) curMesh.material = FoxRenderer.MISSING_MATERIAL; // What happened to our material...

		FoxCache.meshes().set(name, meshes);

		return {meshes: meshes, materials: materials};
	}
}