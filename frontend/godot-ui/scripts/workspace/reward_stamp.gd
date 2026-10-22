extends Control

var accent := Color("7ce4ad")
var earned := false
var symbol := 0

func _ready() -> void:
    custom_minimum_size = Vector2(38, 38)
    mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
    var ink := accent if earned else Color("6b7b8c")
    draw_circle(Vector2(19, 19), 17, Color(ink, 0.12))
    draw_arc(Vector2(19, 19), 16, 0, TAU, 32, ink, 1.5, true)
    match symbol:
        0, 1:
            draw_rect(Rect2(10, 10, 18, 18), ink, false, 1.5)
            draw_line(Vector2(14, 15), Vector2(24, 15), ink, 2)
            draw_line(Vector2(14, 20), Vector2(22, 20), ink, 2)
            draw_line(Vector2(14, 24), Vector2(19, 24), ink, 2)
        2, 4:
            var points := PackedVector2Array()
            for index in range(10):
                var angle := -PI / 2 + index * PI / 5
                points.append(Vector2(19, 19) + Vector2(cos(angle), sin(angle)) * (11 if index % 2 == 0 else 5))
            draw_colored_polygon(points, ink)
        3:
            draw_circle(Vector2(19, 18), 8, ink, false, 2)
            draw_line(Vector2(19, 12), Vector2(19, 18), ink, 2)
            draw_line(Vector2(19, 18), Vector2(24, 21), ink, 2)
        5:
            draw_circle(Vector2(14, 15), 5, ink, false, 2)
            draw_line(Vector2(18, 19), Vector2(27, 28), ink, 3)
            draw_line(Vector2(22, 23), Vector2(25, 20), ink, 3)
        6:
            draw_colored_polygon(PackedVector2Array([Vector2(9, 13), Vector2(14, 19), Vector2(19, 10), Vector2(24, 19), Vector2(29, 13), Vector2(26, 27), Vector2(12, 27)]), ink)
        7:
            draw_rect(Rect2(10, 15, 18, 14), ink, false, 2)
            draw_line(Vector2(19, 13), Vector2(19, 29), ink, 2)
            draw_line(Vector2(9, 19), Vector2(29, 19), ink, 2)
            draw_arc(Vector2(15, 12), 4, 0, TAU, 16, ink, 1.5)
            draw_arc(Vector2(23, 12), 4, 0, TAU, 16, ink, 1.5)
