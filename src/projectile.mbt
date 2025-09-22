// ---------------------------------
// 抛射物 & Debuff 相关定义
// ---------------------------------

/// 定义 Debuff 的具体类型
enum DebuffType {
  Slow(Double) // factor: 速度乘数, e.g., 0.5 代表减速50%
  // 未来可以扩展: Poison(damage_per_sec: Double), Stun, ...
} derive(Eq, Show)

/// 附加在单位身上的 Debuff 组件
struct Debuff {
  kind: DebuffType
  remaining_duration: Double
}

/// 抛射物的命中效果
/// 抛射物的命中效果
pub enum ProjectileEffect {
  SingleTarget(Double)
  AreaOfEffect(Double, Double)
  ApplyDebuff(DebuffType, Double)
  CreateHazardousArea(Double, Double, Double)
} derive(Show)
/// 抛射物组件，描述了一个飞行中的子弹
struct Projectile {
  source_team: Team // 发射者的队伍
  target: @system.Entity
  speed: Double
  effect: ProjectileEffect

  max_turn_rate: Double // 每秒最大转向角度（单位：弧度）
  navigation_constant: Double // 比例导引常数 N
  on_hit_vfx: VFX_Type    // 【新增】视觉效果
  area_effect_vfx: Option[VFX_Type]    // 【新增】视觉效果
}

// --- 全局 Map ---
// 存储所有飞行中的抛射物
let projectiles: Map[@system.Entity, Projectile] = Map::new()
// 存储所有单位当前激活的 Debuff
let active_debuffs: Map[@system.Entity, Array[Debuff]] = Map::new()

const PROJECTILE_HIT_THRESHOLD: Double = 5.0 // 命中判定距离

/// 全新函数：专门处理子弹攻击的执行逻辑
fn execute_bullet_attack(attacker: @system.Entity, target: @system.Entity, stats: CombatStats) -> Unit {
  println("[Log] Executing Bullet Attack from \{attacker} to \{target}")
  
  // 安全地获取攻击者的阵营信息
  if teams.get(attacker) is Some(attacker_team) {
    let effect = if stats.effect_duration > 0.0 {
      // 如果有持续时间，就创建“危险区域”效果
      ProjectileEffect::CreateHazardousArea(
        stats.aoe_radius,       // 从 stats 读取半径
        stats.attack_damage,     // 从 stats 读取每秒伤害
        stats.effect_duration, // 从 stats 读取持续时间
      )
    } else if stats.aoe_radius > 0.0 {
      // 如果没有持续时间，但有范围，就创建“范围伤害”效果
      ProjectileEffect::AreaOfEffect(stats.attack_damage, stats.aoe_radius)
    } else {
      // 否则，就是普通的“单体伤害”效果
      ProjectileEffect::SingleTarget(stats.attack_damage)
    }

    // 2. 定义子弹的视觉外观
    //    未来可以根据单位类型或武器类型改变外观
    let bullet_sprite = @sprite.Sprite::from_shape(
        @sprite.ColoredShape::new(@sprite.Shape::circle(5.0), @sprite.DrawStyle::fill("red")),
        200, // z-index
        layer=@sprite.RenderLayer::game_world(),
    )

    // 3. 调用“军工厂”函数，传入所有配置好的参数
    spawn_projectile(
      attacker,
      target,
      attacker_team,
      effect,
      5.0, // 子弹飞行速度, 未来也可以放入 CombatStats
      bullet_sprite,
      stats.on_hit_vfx, // 【新增】从 stats 中读取特效指令并传递
      stats.area_effect_vfx,
    )
  }
}

fn spawn_projectile(
  source: @system.Entity,
  target: @system.Entity,
  source_team: Team,
  effect: ProjectileEffect,
  speed: Double,
  sprite: @sprite.Sprite, // 直接传递配置好的 Sprite
  on_hit_vfx: VFX_Type,    // 【新增】视觉效果
  area_effect_vfx: Option[VFX_Type]
) -> Unit {
  if @position.positions.get(source) is Some(source_pos) &&
     @position.positions.get(target) is Some(target_pos){
    let projectile_entity = @system.Entity::new()

    // 1. 设置初始位置、Sprite 和抛射物组件
    @position.positions.set(projectile_entity, source_pos.0)
    @sprite.sprites.set(projectile_entity, sprite)
    projectiles.set(projectile_entity, {
      source_team: source_team,
      target: target,
      speed: speed,
      effect: effect,
      max_turn_rate: 0.5, // 每秒最多转 π 弧度 (180度)
      navigation_constant: 1.5, // 一个比较灵敏的制导系数
      on_hit_vfx: on_hit_vfx, // 【新增】将指令存入子弹组件
      area_effect_vfx: area_effect_vfx
    })
    let initial_direction = (target_pos.0 - source_pos.0).normalize()
    @velocity.velocities.set(projectile_entity, initial_direction.scalar_mul(speed))
    // 2. 注意：这里【不】设置速度(velocity)！
    // 速度的计算和更新由 projectile_system 每帧动态处理，以确保始终飞向目标。
  }
}
pub fn projectile_system(_backend: &@system.Backend) -> Unit {
  let delta_seconds = 1.0 / 60.0

  let current_projectiles_snapshot = projectiles.keys()

  for bullet in current_projectiles_snapshot {
    if projectiles.get(bullet) is Some(proj_data) {
      guard bullet.is_alive() else { continue }
      
      if @position.positions.get(bullet) is Some(bullet_pos) &&
         @velocity.velocities.get(bullet) is Some(bullet_vel) {

        // --- 1. 制导逻辑：动态寻找最近的目标进行追踪 ---
        let mut closest_target_for_guidance = None
        let mut min_guidance_distance = 99999.0
        for unit in all_units.val {
          if teams.get(unit) is Some(unit_team) && unit_team != proj_data.source_team {
            if @position.positions.get(unit) is Some(unit_pos) {
              let distance = bullet_pos.0.distance_to(unit_pos.0)
              if distance < min_guidance_distance {
                min_guidance_distance = distance
                closest_target_for_guidance = Some(unit)
              }
            }
          }
        }

        // 如果找到了制导目标，就更新飞行方向
        if closest_target_for_guidance is Some(target) && @position.positions.get(target) is Some(target_pos) {
          let line_of_sight = target_pos.0 - bullet_pos.0
          let los_rate = signed_angle_between(bullet_vel.0, line_of_sight)
          let desired_turn_speed = proj_data.navigation_constant * los_rate
          let max_turn_this_frame = proj_data.max_turn_rate * delta_seconds
          let actual_turn_angle = @kmath.clamp(desired_turn_speed, -max_turn_this_frame, max_turn_this_frame)
          let new_velocity_direction = rotate_vec2d(bullet_vel.0, actual_turn_angle).normalize()
          let final_velocity = new_velocity_direction.scalar_mul(proj_data.speed)
          @velocity.velocities.set(bullet, final_velocity)
        }
        
        // --- 2. 【核心改造】碰撞逻辑：检查是否撞到了“任何”一个敌人 ---
        let mut hit_target = None
        for unit in all_units.val {
            if teams.get(unit) is Some(unit_team) && unit_team != proj_data.source_team {
                if @position.positions.get(unit) is Some(unit_pos) {
                    // 简单的碰撞检测：距离小于单位半径 (例如 32.0)
                    if bullet_pos.0.distance_to(unit_pos.0) < 32.0 {
                        hit_target = Some(unit)
                        break // 只要撞到一个，就停止检查
                    }
                }
            }
        }

        // --- 3. 命中处理 ---
        if hit_target is Some(actual_hit_target) {
          // 从系统中移除子弹
          projectiles.remove(bullet)
          entities_to_cleanup.val.push(bullet)

          // 对【实际撞到的目标】应用效果
          if @position.positions.get(actual_hit_target) is Some(hit_pos) {
            apply_projectile_effect(proj_data, hit_pos.0)
            
          }
        }
      }
    }
  }
}
fn apply_projectile_effect(proj_data: Projectile, hit_pos: @math.Vec2D) -> Unit {
  println("[Log - VFX Request] An on-hit VFX of type '\{proj_data.on_hit_vfx}' was requested.")
  vfx_requests.val.push({
    vfx_type: proj_data.on_hit_vfx,
    position: hit_pos,
    rotation: 0.0,
  })
  match proj_data.effect {
    SingleTarget(damage) => {
      // 委托给“单体伤害”函数
      effect_apply_single_target_damage(proj_data.target, damage)
    }
    AreaOfEffect(damage, radius) => {
      // 委托给“范围伤害”函数
      effect_apply_aoe_damage(hit_pos, radius, damage, proj_data.source_team)
    }
    ApplyDebuff(effect, duration) => {
      // 委托给“施加Debuff”函数
      effect_apply_debuff(proj_data.target, effect, duration)
    }
    CreateHazardousArea(radius, dps, duration) => {
      spawn_hazardous_area(hit_pos, radius, dps, duration, proj_data.source_team, proj_data.area_effect_vfx)
    }
  }
}


fn apply_debuff(target: @system.Entity, effect: DebuffType, duration: Double) -> Unit {
  let new_debuff = { kind: effect, remaining_duration: duration }
  if active_debuffs.get(target) is Some(existing_debuffs) {
    let new_debuffs = existing_debuffs
    new_debuffs.push(new_debuff)
    active_debuffs.set(target, new_debuffs)
  } else {
    active_debuffs.set(target, [new_debuff])
  }
}
//占位符debuff系统
fn debuff_system(_backend: &@system.Backend) -> Unit {
  let delta_seconds = 1.0 / 60.0
  active_debuffs.each(fn(unit, debuffs) {
    // 过滤掉已过期的 Debuff，只保留剩余时间 > 0 的
    let updated_debuffs = debuffs.filter_map(fn(debuff) {
      let new_duration = debuff.remaining_duration - delta_seconds
      if new_duration > 0.0 {
        Some({ ..debuff, remaining_duration: new_duration })
      } else {
        None // 返回 None 会被 filter_map 自动过滤掉
      }
    })

    if updated_debuffs.length() == 0 {
      active_debuffs.remove(unit) // 如果没有 Debuff 了，直接从 Map 中移除
    } else {
      active_debuffs.set(unit, updated_debuffs)
    }
  })
}

pub struct HazardousArea {
  source_team: Team         // 区域所属的队伍
  damage_per_second: Double // 每秒造成的伤害
  radius: Double            // 伤害范围的半径

  mut remaining_duration: Double // 区域剩余的持续时间
  mut tick_timer: Double         // 伤害判定的“心跳”计时器
}

pub let hazardous_areas: Map[@system.Entity, HazardousArea] = Map::new()

fn spawn_hazardous_area(pos: @math.Vec2D, radius: Double, dps: Double, duration: Double, team: Team, vfx_type_opt: Option[VFX_Type]) -> Unit {
  println("[Log Spawning] Spawning hazardous area at (\{pos[X]}, \{pos[Y]})")
  let area_entity = @system.Entity::new()
  @position.positions.set(area_entity, pos)

  if vfx_type_opt is Some(vfx_type) {
    vfx_requests.val.push({
      vfx_type: vfx_type,
      position: pos,
      rotation: 0.0,
    })
  }
  hazardous_areas.set(area_entity, {
    source_team: team,
    damage_per_second: dps,
    radius: radius,
    remaining_duration: duration,
    tick_timer: 1.0, // 初始设为1，让它在1秒后造成第一次伤害
  })
}

pub fn hazardous_area_system(_backend: &@system.Backend) -> Unit {
  let delta_seconds = 1.0 / 60.0
  
  for area_entity in hazardous_areas.keys() {
    if hazardous_areas.get(area_entity) is Some(area_data) {
      
      let updated_data = area_data
      
      updated_data.remaining_duration -= delta_seconds
      
      if updated_data.remaining_duration <= 0.0 {
        entities_to_cleanup.val.push(area_entity)
        hazardous_areas.remove(area_entity)
        // 使用 continue 跳过本次循环的后续逻辑
        continue
      }

      updated_data.tick_timer -= delta_seconds
      if updated_data.tick_timer <= 0.0 {
        updated_data.tick_timer = 1.0 
        if @position.positions.get(area_entity) is Some(area_pos) {
          effect_apply_aoe_damage(
            area_pos.0, 
            updated_data.radius, 
            updated_data.damage_per_second,
            updated_data.source_team,
          )
        }
      }
      
      hazardous_areas.set(area_entity, updated_data)
    }
  }
}