// ---------------------------------
//  视觉特效 (VFX) 系统 (最终修正版)
// ---------------------------------

/// 用一个枚举来描述所有特效的【唯一ID】
pub enum VFX_Type {
  MeleeSlash
  BulletImpact
  PoisonCloud
  PoisonCloudRed
  TankExplosion
  SpeedLow
} derive(Eq, Show, Hash)

/// 用一个枚举来描述特效的【静态外观】
pub enum SpriteTemplate {
  Picture(String, @math.Vec2D)
  Shape(@sprite.Shape, @sprite.DrawStyle)
  Animation(@sprite.Animation, @math.Vec2D)
}
/// 用一个结构体来描述特效的【动态行为】
pub struct VFX_Behavior {
  lifecycle: VFX_Lifecycle

  dynamic_transform: Option[DynamicTransform]
}

/// 【核心】“特效模板”结构体
pub struct VFX_Template {
  sprite_template: SpriteTemplate
  behavior: VFX_Behavior
  z_index: Int
}
pub enum VFX_Lifecycle {
  Timer(Double) // 按计时器管理
  OnAnimationFinish                 // 动画播放完毕后销毁
} derive(Show)
/// 全局的“特效模板库”
pub let vfx_library: Map[VFX_Type, VFX_Template] = Map::new()
// ---------------------------------
//  填充特效模板库
// ---------------------------------
let explosion_frames: Array[@sprite.AnimationFrame] = @sprite.frames_from_atlas(
  "assets/explosion150xA.png",
  8, 
  width=184.5,
  height=150.0,
)

let explosion_animation: @sprite.Animation = @sprite.Animation::new(explosion_frames, loop_=false, rate=1)
fn setup_vfx_library() -> Unit {
  // 模板1：一个简单的子弹命中爆炸效果
  vfx_library.set(VFX_Type::BulletImpact, {
    sprite_template: SpriteTemplate::Animation(
      explosion_animation,
      @math.Vec2D(184.5, 150.0) 
    ),
    behavior: {
      lifecycle: VFX_Lifecycle::OnAnimationFinish,
      dynamic_transform: None,
    },
    z_index: 500,
  })
  vfx_library.set(VFX_Type::PoisonCloud, {
    sprite_template: SpriteTemplate::Shape(
        @sprite.Shape::circle(100.0), 
        @sprite.DrawStyle::fill("rgba(140, 255, 140, 0.5)")),
    behavior: {
      // 【核心】指定生命周期模式
      lifecycle: VFX_Lifecycle::Timer(5.0),
      dynamic_transform: Some({
        rotation_speed: 0.5,
        scale_speed: 1.0,
        scale_amplitude: 0.1,
        _current_angle: 0.0,
        _time_elapsed: 0.0,
      }),
    },
    z_index: 50,
  })
  vfx_library.set(VFX_Type::PoisonCloudRed, {
    sprite_template: SpriteTemplate::Shape(
        @sprite.Shape::circle(100.0), 
        @sprite.DrawStyle::fill("rgba(219, 3, 3, 0.19)")),
    behavior: {
      // 【核心】指定生命周期模式
      lifecycle: VFX_Lifecycle::Timer(5.0),
      dynamic_transform: Some({
        rotation_speed: 0.5,
        scale_speed: 1.0,
        scale_amplitude: 0.1,
        _current_angle: 0.0,
        _time_elapsed: 0.0,
      }),
    },
    z_index: 50,
  })
  vfx_library.set(VFX_Type::SpeedLow, {
    sprite_template: SpriteTemplate::Shape(
        @sprite.Shape::rect(5,5,0.775), 
        @sprite.DrawStyle::fill("rgba(17, 0, 255, 1)")),
    behavior: {
      // 【核心】指定生命周期模式
      lifecycle: VFX_Lifecycle::Timer(0.5),
      dynamic_transform: Some({
        rotation_speed: 0.5,
        scale_speed: 1.0,
        scale_amplitude: 0.1,
        _current_angle: 0.0,
        _time_elapsed: 0.0,
      }),
    },
    z_index: 120,
  })
}

// --- 特效事件与管理组件 ---

/// 【核心修正】VFX_Request 结构体定义，移除逗号
pub struct VFX_Request {
  vfx_type: VFX_Type
  position: @math.Vec2D
  rotation: Double
}

pub let vfx_requests: Ref[Array[VFX_Request]] = Ref::new([])

/// 【核心修正】VFX_Instance 结构体定义，移除 mut
pub struct VFX_Instance {
  total_duration: Double
  remaining_duration: Double
}
pub let vfx_instances: Map[@system.Entity, VFX_Lifecycle] = Map::new()

//  “特效生成器” 
pub fn vfx_spawner_system(_backend: &@system.Backend) -> Unit {
  for request in vfx_requests.val {
    if vfx_library.get(request.vfx_type) is Some(template) {
      let vfx_entity = @system.Entity::new()
      @position.positions.set(vfx_entity, request.position)
      let sprite_component = match template.sprite_template {
        SpriteTemplate::Picture(path, dims) => {
          let pic = @sprite.Picture::new(dims, path)
          @sprite.Sprite::from_picture(pic, template.z_index, offset=dims.scalar_div(-2.0), layer=@sprite.RenderLayer::game_world())
        }
        SpriteTemplate::Shape(shape, style) => {
          let graphic = @sprite.ColoredShape::new(shape, style)
          @sprite.Sprite::from_shape(graphic, template.z_index, layer=@sprite.RenderLayer::game_world())
        }
        SpriteTemplate::Animation(anim, dims) => {
          let offset_to_center = dims.scalar_div(-2.0)
          @sprite.Sprite::from_animation(anim, template.z_index, offset=offset_to_center, layer=@sprite.RenderLayer::game_world())
        }
      }

      @sprite.sprites.set(vfx_entity, sprite_component)
      if template.sprite_template is Animation(anim, _) {
        @sprite.play_animation(vfx_entity, anim)
      }
      
      vfx_instances.set(vfx_entity, template.behavior.lifecycle)
      if template.behavior.dynamic_transform is Some(dt) {
        dynamic_transforms.set(vfx_entity, dt)
      }
    }
  }
  vfx_requests.val.clear()
}

/// 系统2：“特效更新器”
pub fn vfx_update_system(_backend: &@system.Backend) -> Unit {
  let delta_seconds = 1.0 / 60.0

  for entity in vfx_instances.keys() {
    if vfx_instances.get(entity) is Some(instance_lifecycle) {

      let mut should_destroy = false

      // 【核心】使用 match 语句，为不同类型的生命周期执行不同逻辑
      match instance_lifecycle {
        VFX_Lifecycle::Timer(remaining) => {
          let new_duration = remaining - delta_seconds
          if new_duration <= 0.0 {
            should_destroy = true
          } else {
            vfx_instances.set(entity, VFX_Lifecycle::Timer(new_duration))
          }
        }
        VFX_Lifecycle::OnAnimationFinish => {
          // 【核心】在这里，我们整合了您之前成功的 cleanup_effects_system 的逻辑！
          if @sprite.is_animation_finished(entity) {
            should_destroy = true
          }
        }
      }

      if should_destroy {
        entities_to_cleanup.val.push(entity)
        vfx_instances.remove(entity)
      }
    }
  }
}