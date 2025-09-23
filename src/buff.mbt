pub enum BuffType {
  AddDamage(Double)          // 增加固定数值的伤害
  MultiplyDamage(Double)       // 按百分比增加伤害 (例如 1.2 代表增加20%)
  AddCritRate(Double)          // 增加暴击率 (例如 0.1 代表增加10%)
  AddEffectDuration(Double)    // 增加技能效果的持续时间
  MultiplyCooldown(Double)     // 乘以一个系数来改变攻击冷却 (例如 0.8 代表冷却缩短20%)
  AddAttackRange(Double)       // 增加攻击范围
  MultiplySpeed(Double) // 改变移动速度 (例如 1.5 代表速度提高50%)
} derive(Show)

// 2. 定义一个激活在单位身上的 Buff 实例
pub struct BuffInstance {
  buff_type: BuffType
  remaining_duration: Double
}

// 3. 创建一个全局的 Map 来存储所有单位的 Buff
pub let active_buffs: Map[@system.Entity, Array[BuffInstance]] = Map::new()


fn buff_system(_backend: &@system.Backend) -> Unit {
  let delta_seconds = 1.0 / 60.0
  
  for unit in active_buffs.keys() {
    if active_buffs.get(unit) is Some(buff_list) {
      
      let updated_buff_list = buff_list.filter_map(fn(buff) {
        let new_duration = buff.remaining_duration - delta_seconds
        if new_duration > 0.0 {
          Some({ ..buff, remaining_duration: new_duration })
        } else {
          None
        }
      })

      if updated_buff_list.length() == 0 {
        active_buffs.remove(unit)
      } else {
        active_buffs.set(unit, updated_buff_list)
      }
    }
  }
}

fn get_computed_stats(unit: @system.Entity) -> Option[CombatStats] {
  if combat_stats.get(unit) is Some(base_stats) {
    if active_buffs.get(unit) is Some(buff_list) {
      // computed_stats 变量需要是 mut，因为我们会不断用新副本替换它
      let mut computed_stats = base_stats
      
      for buff in buff_list {
        match buff.buff_type {
          AddDamage(value) => {
            // 不要原地修改，而是创建一个新副本并替换
            computed_stats = { 
              ..computed_stats, 
              attack_damage: computed_stats.attack_damage + value 
            }
          }
          MultiplyDamage(factor) => {
            computed_stats = { 
              ..computed_stats, 
              attack_damage: computed_stats.attack_damage * factor
            }
          }
          AddCritRate(value) => {
            computed_stats = {
              ..computed_stats,
              crit_rate: computed_stats.crit_rate + value
            }
          }
          AddEffectDuration(value) => {
            computed_stats = {
              ..computed_stats,
              effect_duration: computed_stats.effect_duration + value
            }
          }
          MultiplyCooldown(factor) => {
            computed_stats = {
              ..computed_stats,
              attack_cooldown: computed_stats.attack_cooldown * factor
            }
          }
          AddAttackRange(value) => {
            computed_stats = {
              ..computed_stats,
              attack_range: computed_stats.attack_range + value
            }
          }
          _ => () 
        }
      }
      
      return Some(computed_stats)

    } else {
      return Some(base_stats)
    }
  }

  return None
}

pub fn add_buff(target: @system.Entity, buff_type: BuffType, duration: Double) -> Unit {
  let new_buff = { buff_type: buff_type, remaining_duration: duration }
  
  if active_buffs.get(target) is Some(existing_buffs) {
    let new_buff_list = existing_buffs
    new_buff_list.push(new_buff)
    active_buffs.set(target, new_buff_list)
  } else {
    active_buffs.set(target, [new_buff])
  }
  
}
fn get_computed_movement_stats(unit: @system.Entity) -> Option[MovementStats] {
  if movement_stats.get(unit) is Some(base_stats) {
    if active_buffs.get(unit) is Some(buff_list) {
      
      let mut computed_stats = base_stats
      
      for buff in buff_list {
        match buff.buff_type {
          MultiplySpeed(factor) => {
            computed_stats = { 
              ..computed_stats, 
              speed: computed_stats.speed * factor 
            }
          }
          _ => () 
        }
      }
      return Some(computed_stats)
    } else {
      return Some(base_stats)
    }
  }
  return None
}