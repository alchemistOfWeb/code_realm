extends Node
## Глобальная шина сигналов между системами (UI, навигация, уведомления).

## Открыть экран поверх текущего. screen — ключ из Main.SCREENS.
signal navigate(screen: String, params: Dictionary)
## Вернуться на предыдущий экран.
signal navigate_back()
## Вернуться на корневой экран (WorldTree).
signal navigate_home()
## Всплывающее уведомление. kind: "info" | "success" | "warning" | "error" | "xp"
signal toast(text: String, kind: String)
## Прогресс знаний изменился (изучение / сброс). spec_id может быть "".
signal progress_changed(spec_id: String)
## Заметки для Claude экспортированы в файл.
signal notes_exported(path: String)
## Бой завершён: {won, enemy_id, context, xp, gold, energy, cards, hp_left}
signal combat_finished(result: Dictionary)
## Диалог завершён: actions — действия для мира ([{type: "combat"|"open_gate"|"reveal_map"|..., ...}])
signal dialogue_finished(npc_id: String, actions: Array)
## Загадка у двери: solved — открыт ли проход
signal riddle_finished(riddle_id: String, solved: bool)
## Сейф: opened — исправлен ли код
signal safe_finished(safe_id: String, opened: bool)


func go(screen: String, params: Dictionary = {}) -> void:
	navigate.emit(screen, params)


func back() -> void:
	navigate_back.emit()


func notify(text: String, kind: String = "info") -> void:
	toast.emit(text, kind)
