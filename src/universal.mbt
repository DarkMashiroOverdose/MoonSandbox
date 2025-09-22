/// ------------------------
/// 实用函数
/// ------------------------
fn min_double(a: Double, b: Double) -> Double {
  if a < b { a } else { b }
}

fn max_double(a: Double, b: Double) -> Double {
  if a > b { a } else { b }
}
const PI = 3.14159
// 计算两个向量之间的带符号夹角 (弧度)
fn signed_angle_between(v1: @math.Vec2D, v2: @math.Vec2D) -> Double {

  let v1_norm = v1.normalize()
  let v2_norm = v2.normalize()
  let dot = v1_norm.dot(v2_norm)
  let cross = v1_norm[X] * v2_norm[Y] - v1_norm[Y] * v2_norm[X]
  return @kmath.atan2(cross, dot) // 使用 kmath 提供的 atan2
}

// 将一个向量旋转指定的角度 (弧度)
fn rotate_vec2d(vec: @math.Vec2D, angle_rad: Double) -> @math.Vec2D {
  let cos_a = @kmath.cos(angle_rad)
  let sin_a = @kmath.sin(angle_rad)
  let new_x = vec[X] * cos_a - vec[Y] * sin_a
  let new_y = vec[X] * sin_a + vec[Y] * cos_a
  return @math.Vec2D(new_x, new_y)
} 

// 将一个值限制在最小和最大值之间
fn clamp_double(val: Double, min: Double, max: Double) -> Double {
  // 新数学库直接提供了 clamp 函数！
  return @kmath.clamp(val, min, max)
}


/// 在两个二维向量之间进行线性插值
/// @param p1 起点向量
/// @param p2 终点向量
/// @param ratio 插值比例 (0.0 到 1.0)
/// @return @math.Vec2D 插值后的新向量
fn vec2d_lerp(p1: @math.Vec2D, p2: @math.Vec2D, ratio: Double) -> @math.Vec2D {
  return p1 + (p2 - p1).scalar_mul(ratio)
}