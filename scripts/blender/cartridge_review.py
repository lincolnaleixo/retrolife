#!/usr/bin/env python3
"""Original NTSC cartridge review candidate. Metres, Cycles CPU, no external mesh.

blender -b --factory-startup --python-exit-code 1 --python scripts/blender/cartridge_review.py -- --out build/cartridge-review
This does not replace the active M2 asset or claim physical calibration.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import math
import sys
from pathlib import Path
import bpy
import bmesh
from mathutils import Matrix, Vector
from bpy_extras.object_utils import world_to_camera_view

MM = 0.001
MODEL = []
FRONT = []
BACK = []
CAMERAS = {}
ASSET = 'retrolife.snes.ntsc.cartridge.review.r1'


def active(obj):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def apply(obj, modifier):
    active(obj)
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def normals(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    if bm.calc_volume(signed=True) < 0:
        bmesh.ops.reverse_faces(bm, faces=list(bm.faces))
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def bevel(obj, width, segments=4):
    mod = obj.modifiers.new('Mould edge radii', 'BEVEL')
    mod.width = width * MM
    mod.segments = segments
    mod.limit_method = 'ANGLE'
    mod.angle_limit = math.radians(28)
    mod.use_clamp_overlap = True
    apply(obj, mod)


def finish(obj):
    normals(obj)
    for face in obj.data.polygons:
        face.use_smooth = True
    if hasattr(obj.data, 'set_sharp_from_angle'):
        obj.data.set_sharp_from_angle(angle=math.radians(45))
    mod = obj.modifiers.new('Preserve flat moulded faces', 'WEIGHTED_NORMAL')
    mod.keep_sharp = True
    mod.weight = 50
    apply(obj, mod)


def material(name, color, roughness=.4, metallic=0, grain=False):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Metallic'].default_value = metallic
    if grain:
        tex = nodes.new('ShaderNodeTexNoise')
        tex.inputs['Scale'].default_value = 4800
        tex.inputs['Detail'].default_value = 2
        coords = nodes.new('ShaderNodeTexCoord')
        bump = nodes.new('ShaderNodeBump')
        bump.inputs['Strength'].default_value = .12
        bump.inputs['Distance'].default_value = .000012
        mat.node_tree.links.new(coords.outputs['Object'], tex.inputs['Vector'])
        mat.node_tree.links.new(tex.outputs['Fac'], bump.inputs['Height'])
        mat.node_tree.links.new(bump.outputs['Normal'], bsdf.inputs['Normal'])
    return mat


def record(obj, mat, group=None):
    obj.data.materials.append(mat)
    MODEL.append(obj)
    if group is not None:
        group.append(obj)
    return obj


def rounded_outline(width, height, radius, bottom=0, segments=10):
    points = []
    for cx, cz, start in ((width/2-radius, bottom+radius, -90),
                          (width/2-radius, bottom+height-radius, 0),
                          (-width/2+radius, bottom+height-radius, 90),
                          (-width/2+radius, bottom+radius, 180)):
        for step in range(segments+1):
            angle = math.radians(start+step*90/segments)
            points.append((cx+radius*math.cos(angle), cz+radius*math.sin(angle)))
    return points


def prism(name, outline, y0, y1, radius=0):
    n = len(outline)
    vertices = [(x*MM, y*MM, z*MM) for y in (y0, y1) for x, z in outline]
    faces = [tuple(reversed(range(n))), tuple(range(n, 2*n))]
    faces += [(i, (i+1)%n, (i+1)%n+n, i+n) for i in range(n)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    normals(obj)
    if radius:
        bevel(obj, radius)
    return obj


def box(name, dimensions, center, radius=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=tuple(v*MM for v in center))
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = tuple(v*MM for v in dimensions)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if radius:
        bevel(obj, radius)
    return obj


def cylinder(name, radius, depth, center, vertices=64):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius*MM,
        depth=depth*MM, location=tuple(v*MM for v in center), rotation=(math.pi/2, 0, 0))
    obj = bpy.context.object
    obj.name = name
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return obj


def boolean(obj, cutter, operation='DIFFERENCE'):
    mod = obj.modifiers.new(operation+' '+cutter.name, 'BOOLEAN')
    mod.operation = operation
    mod.solver = 'EXACT'
    mod.object = cutter
    apply(obj, mod)
    bpy.data.objects.remove(cutter, do_unlink=True)


def build():
    plastic = material('Neutral ABS', (.46, .455, .48), grain=True)
    steel = material('Security screw metal', (.20, .17, .11), .3, .8)
    pcbmat = material('PCB engineering placeholder', (.015, .13, .055), .6)
    gold = material('Contact plating', (.64, .35, .065), .28, .75)
    labelmat = material('Replaceable neutral label', (.025, .031, .041), .52)
    outline = [(-65.8,0),(-67.3,.5),(-68,1.6),(-68,82),(-67.4,83.5),
        (-66,84.2),(-48.2,84.2),(-46.6,84.6),(-45.4,85.8),(-44.2,87.5),
        (-43.3,88),(43.3,88),(44.2,87.5),(45.4,85.8),(46.6,84.6),
        (48.2,84.2),(66,84.2),(67.4,83.5),(68,82),(68,1.6),(67.3,.5),(65.8,0)]
    front = record(prism('Front shell', outline, -9, -.10, .6), plastic, FRONT)
    rear = record(prism('Rear shell', outline, .10, 10, .65), plastic, BACK)
    center = [(-46.5,.3),(-46.5,83.8),(-45.2,85.4),(-43.1,88),
              (43.1,88),(45.2,85.4),(46.5,83.8),(46.5,.3)]
    boolean(front, prism('Integrated center moulding', center, -10, -8.2, .65), 'UNION')
    inside = [(x*.953, 2+z*.955) for x,z in outline]
    boolean(front, prism('Front cavity', inside, -7.2, 1, .5))
    boolean(rear, prism('Rear cavity', inside, -1, 8.2, .5))
    boolean(front, prism('Label recess', rounded_outline(84.5,37.8,2.3,47.4), -11,-9.55))
    boolean(front, prism('Continuous shallow locking channel', rounded_outline(85,5.8,2.8,28.8), -11,-8.8))
    # The middle land is shallower than the channel, not two disconnected capsules.
    boolean(front, box('Center channel land', (24,1.4,6.3), (0,-8.3,31.7), .2), 'UNION')
    for side in (-1,1):
        for z in (14,28,42,56,70):
            boolean(front, box('Wing groove', (22,7,.65), (side*58.2,-11.7,z), .18))
        boolean(front, cylinder('Screw recess',2.25,2,(side*55.6,-9.1,7)))
        screw = cylinder('Six notch security screw',1.4,.55,(side*55.6,-8.3,7))
        for i in range(6):
            angle = i*math.pi/3
            boolean(screw,cylinder('Security recess',.32,1,
                (side*55.6+1.32*math.cos(angle),-8.3,7+1.32*math.sin(angle)),24))
        bevel(screw,.06,3)
        finish(screw)
        record(screw,steel,FRONT)
    boolean(rear,prism('Rear label recess',rounded_outline(86,28,2,16),9.5,11))
    for z in (14,28,42,56,70):
        if 16<z<44:
            for side in (-1,1):
                boolean(rear,box('Rear wing groove',(22,2,.55),(side*58.2,10.65,z),.15))
        else:
            boolean(rear,box('Rear full groove',(136,2,.55),(0,10.65,z),.15))
    for side in (-1,1):
        boolean(rear,prism('Top retention recess',
            [(x+side*49,z) for x,z in rounded_outline(4,6,1,77)],9.35,11))
    # Underside opening retains front and rear rims. No opaque filler inside it.
    for shell in (front,rear):
        boolean(shell,box('Connector aperture',(94,10.6,10),(0,0,1.4),1))
        bevel(shell,.10,3)
        finish(shell)
    record(box('PCB visual blockout',(83,1.2,60),(0,0,33.5),.2),pcbmat)
    for side in (-1,1):
        for index in range(23):
            record(box('Contact %s %02d'%(side,index),(1.8,.12,5.6),
                       ((index-11)*3.2,side*.66,6.4),.04),gold)
    border=rounded_outline(83.4,36.7,1.9,47.95)
    mesh=bpy.data.meshes.new('Label UV mesh')
    mesh.from_pydata([(x*MM,-9.61*MM,z*MM) for x,z in border],[],[tuple(range(len(border)))])
    mesh.update()
    label=bpy.data.objects.new('LabelSurface',mesh)
    bpy.context.scene.collection.objects.link(label)
    uv=mesh.uv_layers.new(name='UVMap')
    for loop in mesh.loops:
        v=mesh.vertices[loop.vertex_index].co
        uv.data[loop.index].uv=((v.x/MM+41.7)/83.4,(v.z/MM-47.95)/36.7)
    record(label,labelmat,FRONT)
    return front,rear,label


def rotation(direction, up):
    forward=-Vector(direction).normalized()
    right=forward.cross(Vector(up)).normalized()
    vertical=right.cross(forward).normalized()
    return Matrix((right,vertical,-forward)).transposed().to_quaternion()


def points():
    bpy.context.view_layer.update()
    graph=bpy.context.evaluated_depsgraph_get()
    result=[]
    for obj in MODEL:
        if not obj.hide_render:
            obj=obj.evaluated_get(graph)
            result.extend(obj.matrix_world@Vector(corner) for corner in obj.bound_box)
    return result


def camera(name,direction,up=(0,0,1),perspective=False):
    scene=bpy.context.scene
    corners=points()
    lo=Vector(tuple(min(p[i] for p in corners) for i in range(3)))
    hi=Vector(tuple(max(p[i] for p in corners) for i in range(3)))
    center=(lo+hi)/2
    data=bpy.data.cameras.new(name)
    obj=bpy.data.objects.new(name,data)
    scene.collection.objects.link(obj)
    obj.rotation_mode='QUATERNION'
    obj.rotation_quaternion=rotation(direction,up)
    data.clip_start=.001
    data.clip_end=5
    data.type='PERSP' if perspective else 'ORTHO'
    data.lens=65
    data.sensor_fit='HORIZONTAL'
    data.ortho_scale=.16
    distance=.40
    for _ in range(140):
        obj.location=center+Vector(direction).normalized()*distance
        bpy.context.view_layer.update()
        projected=[world_to_camera_view(scene,obj,p) for p in corners]
        good=all(.065<=p.x<=.935 and .065<=p.y<=.935 and p.z>0 for p in projected)
        if good:
            break
        if perspective: distance*=1.035
        else: data.ortho_scale*=1.035
    else: raise RuntimeError('Camera could not contain all geometry: '+name)
    CAMERAS[name]={'boundsNdc':[min(p.x for p in projected),min(p.y for p in projected),
                      max(p.x for p in projected),max(p.y for p in projected)],'perspective':perspective}
    return obj


def setup(width,samples):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene=bpy.context.scene
    scene.unit_settings.system='METRIC'
    scene.unit_settings.scale_length=1
    scene.render.engine='CYCLES'
    scene.cycles.device='CPU'
    scene.cycles.samples=samples
    scene.cycles.seed=7
    scene.cycles.use_animated_seed=False
    scene.cycles.use_denoising=True
    scene.render.resolution_x=width
    scene.render.resolution_y=round(width*.75)
    scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG'
    scene.render.image_settings.color_mode='RGBA'
    scene.render.film_transparent=True
    scene.view_settings.view_transform='AgX'
    scene.view_settings.exposure=0
    world=bpy.data.worlds.new('Studio environment')
    world.use_nodes=True
    world.node_tree.nodes['Background'].inputs['Color'].default_value=(.8,.8,.8,1)
    world.node_tree.nodes['Background'].inputs['Strength'].default_value=.30
    scene.world=world
    target=Vector((0,0,.044))
    for name,loc,power,size in (
        ('Key',(-.16,-.22,.22),12,.20),('Fill',(.18,-.10,.12),5,.18),
        ('Rear softbox',(.05,.22,.18),9,.18),('Underside fill',(0,-.07,-.12),2,.15)):
        data=bpy.data.lights.new(name,'AREA')
        data.energy=power
        data.shape='DISK'
        data.size=size
        obj=bpy.data.objects.new(name,data)
        scene.collection.objects.link(obj)
        obj.location=loc
        obj.rotation_euler=(target-obj.location).to_track_quat('-Z','Y').to_euler()


def validate(shells):
    stats={}
    for obj in shells:
        bm=bmesh.new();bm.from_mesh(obj.data)
        bad=sum(not e.is_manifold for e in bm.edges)
        volume=abs(bm.calc_volume())
        stats[obj.name]={'nonManifoldEdges':bad,'volumeM3':volume,'vertices':len(bm.verts)}
        bm.free()
        if bad or volume<=0: raise RuntimeError('Invalid shell topology: '+str(stats))
    return stats


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--width',type=int,default=1400)
    parser.add_argument('--samples',type=int,default=64)
    parser.add_argument('--label',type=Path)
    parser.add_argument('--hero-only',action='store_true')
    opts=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    out=opts.out.resolve();out.mkdir(parents=True,exist_ok=True)
    setup(opts.width,opts.samples)
    front,rear,label=build()
    topology=validate((front,rear))
    renders=[]
    def shot(name,direction,up=(0,0,1),perspective=False):
        cam=camera(name,direction,up,perspective)
        bpy.context.scene.camera=cam
        bpy.context.scene.render.filepath=str(out/(name+'.png'))
        bpy.ops.render.render(write_still=True)
        renders.append(name+'.png')
        return cam
    label.hide_render=True
    shot('clay-front',(0,-1,0))
    shot('clay-three-quarter',(1,-2.6,.8),perspective=True)
    label.hide_render=False
    shot('neutral-front',(0,-1,0))
    hero=shot('neutral-three-quarter',(1,-2.6,.8),perspective=True)
    if not opts.hero_only:
        shot('rear',(0,1,0))
        shot('rear-three-quarter',(-1,2.6,.8),perspective=True)
        shot('left',(-1,0,0));shot('right',(1,0,0))
        shot('top',(0,0,1),(0,1,0));shot('bottom',(0,0,-1),(0,-1,0))
        for obj in FRONT: obj.location.y-=.022
        for obj in BACK: obj.location.y+=.022
        shot('exploded',(1,-2.6,.8),perspective=True)
        for obj in FRONT: obj.location.y+=.022
        for obj in BACK: obj.location.y-=.022
    bpy.context.scene.camera=hero
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action='DESELECT')
    for obj in MODEL:
        obj.select_set(True)
        obj['assetId']=ASSET
        obj['physicalCalibrationComplete']=False
    bpy.context.view_layer.objects.active=front
    bpy.ops.export_scene.gltf(filepath=str(out/'cartridge.glb'),export_format='GLB',
        use_selection=True,export_apply=True,export_cameras=False,export_lights=False,export_extras=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(out/'cartridge.blend'),compress=True)
    # Optional commercial art is review-only and never saved into the neutral assets.
    if opts.label:
        mat=label.data.materials[0]
        tex=mat.node_tree.nodes.new('ShaderNodeTexImage')
        tex.image=bpy.data.images.load(str(opts.label.resolve()))
        mat.node_tree.links.new(tex.outputs['Color'],mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
        shot('reference-label-front',(0,-1,0))
        shot('reference-label-three-quarter',(1,-2.6,.8),perspective=True)
    paths=['cartridge.blend','cartridge.glb',*renders]
    report={'assetId':ASSET,'renderer':'Cycles CPU','blenderVersion':bpy.app.version_string,
        'units':'metres','physicalCalibrationComplete':False,'visualApproved':False,
        'activeM2Replaced':False,'geometricLicense':'CC0-1.0','topology':topology,
        'cameraChecks':CAMERAS,'commercialLabelInAsset':False,
        'source':'Original review geometry; photo-estimated proportions, not a physical scan',
        'reference':'https://media.gamestop.com/i/gamestop/10125270/Super-Mario-World---Super-Nintendo',
        'files':{name:hashlib.sha256((out/name).read_bytes()).hexdigest() for name in paths}}
    (out/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
    print('RETROLIFE_BLENDER_REVIEW_OK',json.dumps(topology),flush=True)


if __name__=='__main__': main()
