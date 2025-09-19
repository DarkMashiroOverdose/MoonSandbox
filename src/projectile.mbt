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
enum ProjectileEffect {
  SingleTarget(Double)            // 包含一个 Double 类型的伤害值
  AreaOfEffect(Double, Double)    // 包含伤害值(Double)和半径(Double)
  ApplyDebuff(DebuffType, Double) // 包含 Debuff 类型和持续时间(Double)
} derive(Show)
/// 抛射物组件，描述了一个飞行中的子弹
struct Projectile {
  source_team: Team // 发射者的队伍
  target: @system.Entity
  speed: Double
  effect: ProjectileEffect
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
    // 1. 定义子弹的命中效果
    //    这里可以根据 stats 或者其他逻辑变得更复杂
    let effect = ProjectileEffect::AreaOfEffect(stats.attack_damage,100.0)

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
      bullet_sprite
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
) -> Unit {
  if @position.positions.get(source) is Some(source_pos) {
    let projectile_entity = @system.Entity::new()

    // 1. 设置初始位置、Sprite 和抛射物组件
    @position.positions.set(projectile_entity, source_pos.0)
    @sprite.sprites.set(projectile_entity, sprite)
    projectiles.set(projectile_entity, {
      source_team: source_team,
      target: target,
      speed: speed,
      effect: effect,
    })
    
    // 2. 注意：这里【不】设置速度(velocity)！
    // 速度的计算和更新由 projectile_system 每帧动态处理，以确保始终飞向目标。
  }
}

/// 抛射物系统：处理所有子弹的飞行、寻的、命中检测和效果应用
fn projectile_system(_backend: &@system.Backend) -> Unit {
  projectiles.each(fn(proj_entity, proj_data) {
    // 安全地获取抛射物和目标的位置
    if @position.positions.get(proj_entity) is Some(proj_pos) {
      if @position.positions.get(proj_data.target) is Some(target_pos) && proj_data.target.is_alive() {
        let distance = proj_pos.0.distance_to(target_pos.0)

        // 1. 命中检测
        if distance < PROJECTILE_HIT_THRESHOLD {
          // 命中！应用效果并清理子弹
          apply_projectile_effect(proj_data, target_pos.0) // 传入命中位置用于AoE
          entities_to_cleanup.val.push(proj_entity)
          @velocity.velocities.remove(proj_entity) // 停止移动

          ///////////////////临时测试爆炸效果///////////////////
          // 1. 创建一个新的、临时的实体用于播放特效
          let effect_entity = @system.Entity::new()

          // 2. 将特效实体的初始位置设置在被攻击的目标身上
          @position.positions.set(effect_entity, target_pos.0.add(@math.Vec2D(185.0 / -2, 150.0/-2))) // 稍微往上偏移一点

          // 3. 在这个新实体上播放我们准备好的、不循环的爆炸动画
          @sprite.play_animation(
            effect_entity,
            explosion_animation,
            layer=@sprite.RenderLayer::game_world(),
          )

          // 2. 手动获取并更新 Sprite 的 zindex
          if @sprite.sprites.get(effect_entity) is Some(sprite) {
            let updated_sprite = { ..sprite, zindex: 500 }
            @sprite.sprites.set(effect_entity, updated_sprite)
          }
          one_shot_effects.add(effect_entity)
          ///////////////////临时测试爆炸效果///////////////////
          
          projectiles.remove(proj_entity) // 从系统中移除
          
        } else {
          // 2. 持续寻的
          let direction = (target_pos.0 - proj_pos.0).normalize()
          let velocity = direction.scalar_mul(proj_data.speed)
          @velocity.velocities.set(proj_entity, velocity)
        }

      } else {
        // 目标丢失或死亡，清理子弹
        entities_to_cleanup.val.push(proj_entity)
        projectiles.remove(proj_entity)
      }
    }
  })
}

/// 效果应用函数：根据 ProjectileEffect 类型执行不同逻辑
fn apply_projectile_effect(proj_data: Projectile, hit_pos: @math.Vec2D) -> Unit {
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