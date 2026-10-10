#!/usr/bin/env python3
"""로컬 및 GVFS URI를 탐색하는 간단한 GTK 파일 탐색기."""

import os
import re
import sys

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gio", "2.0")
from gi.repository import Gio, Gtk


APPLICATION_ID = "com.github.devchan64.Ubuntu26FileExplorer"


def natural_name_key(name: str) -> list[tuple[int, object]]:
    """사람이 기대하는 순서로 파일 이름을 비교할 키를 만든다."""
    normalized = re.sub(r"[-._]", "", name.casefold())
    key = [(0, int(part)) if part.isdigit() else (1, part) for part in re.split(r"(\d+)", normalized)]
    return key + [(2, name.casefold())]


def format_size(size: int) -> str:
    """바이트 단위를 파일 목록에 읽기 쉬운 형태로 표시한다."""
    units = ("B", "KiB", "MiB", "GiB", "TiB")
    value = float(size)
    for unit in units:
        if value < 1024 or unit == units[-1]:
            return f"{value:.0f} {unit}" if unit == "B" else f"{value:.1f} {unit}"
        value /= 1024
    return f"{size} B"


class FileExplorer(Gtk.Application):
    """GIO/GVFS를 통해 로컬 및 SMB 위치를 표시한다."""

    def __init__(self) -> None:
        super().__init__(application_id=APPLICATION_ID)
        self.current_file = Gio.File.new_for_path(os.path.expanduser("~"))
        self.history: list[str] = []
        self.history_index = -1
        self.descending = False
        self.window: Gtk.ApplicationWindow | None = None
        self.location_entry: Gtk.Entry | None = None
        self.file_list: Gtk.ListBox | None = None
        self.status_label: Gtk.Label | None = None
        self.back_button: Gtk.Button | None = None
        self.forward_button: Gtk.Button | None = None
        self.rename_button: Gtk.Button | None = None
        self.delete_button: Gtk.Button | None = None
        self.select_all_button: Gtk.Button | None = None
        self.clear_selection_button: Gtk.Button | None = None
        self.search_entry: Gtk.SearchEntry | None = None
        self.entries: list[tuple[Gio.File, Gio.FileInfo]] = []
        self.multi_select_enabled = False

    def do_activate(self) -> None:
        if self.window is None:
            self._build_window()
            self._open_file(self.current_file, add_history=True)
        self.window.present()

    def _build_window(self) -> None:
        self.window = Gtk.ApplicationWindow(application=self, title="파일 탐색기")
        self.window.set_default_size(900, 620)

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        root.set_margin_top(12)
        root.set_margin_bottom(12)
        root.set_margin_start(12)
        root.set_margin_end(12)
        self.window.set_child(root)

        navigation_bar = Gtk.Box(spacing=6)
        root.append(navigation_bar)

        self.back_button = Gtk.Button.new_from_icon_name("go-previous-symbolic")
        self.back_button.set_tooltip_text("뒤로")
        self.back_button.connect("clicked", self._go_back)
        navigation_bar.append(self.back_button)

        self.forward_button = Gtk.Button.new_from_icon_name("go-next-symbolic")
        self.forward_button.set_tooltip_text("앞으로")
        self.forward_button.connect("clicked", self._go_forward)
        navigation_bar.append(self.forward_button)

        up_button = Gtk.Button.new_from_icon_name("go-up-symbolic")
        up_button.set_tooltip_text("상위 폴더")
        up_button.connect("clicked", self._go_up)
        navigation_bar.append(up_button)

        home_button = Gtk.Button.new_from_icon_name("go-home-symbolic")
        home_button.set_tooltip_text("홈 폴더")
        home_button.connect("clicked", self._go_home)
        navigation_bar.append(home_button)

        network_button = Gtk.Button.new_from_icon_name("network-workgroup-symbolic")
        network_button.set_tooltip_text("네트워크 탐색")
        network_button.connect("clicked", self._browse_network)
        navigation_bar.append(network_button)

        smb_button = Gtk.Button(label="SMB 탐색")
        smb_button.set_tooltip_text("SMB/NAS 네트워크 위치 탐색")
        smb_button.connect("clicked", self._browse_smb)
        navigation_bar.append(smb_button)

        reload_button = Gtk.Button.new_from_icon_name("view-refresh-symbolic")
        reload_button.set_tooltip_text("새로고침")
        reload_button.connect("clicked", lambda *_: self._refresh())
        navigation_bar.append(reload_button)

        self.location_entry = Gtk.Entry(placeholder_text="경로 또는 smb://서버/공유이름")
        self.location_entry.set_hexpand(True)
        self.location_entry.connect("activate", self._open_location)
        navigation_bar.append(self.location_entry)

        action_bar = Gtk.Box(spacing=6)
        root.append(action_bar)

        selection_mode_button = Gtk.ToggleButton(label="선택 모드")
        selection_mode_button.set_tooltip_text("다중 선택과 일괄 작업을 켜거나 끕니다")
        selection_mode_button.connect("toggled", self._toggle_selection_mode)
        action_bar.append(selection_mode_button)

        sort_button = Gtk.Button(label="이름: 오름차순")
        sort_button.connect("clicked", self._toggle_sort)
        action_bar.append(sort_button)
        self.sort_button = sort_button

        self.rename_button = Gtk.Button(label="선택 항목 이름 변경")
        self.rename_button.set_sensitive(False)
        self.rename_button.connect("clicked", self._show_rename_dialog)
        action_bar.append(self.rename_button)

        self.delete_button = Gtk.Button(label="삭제")
        self.delete_button.set_sensitive(False)
        self.delete_button.connect("clicked", self._confirm_delete_selected)
        action_bar.append(self.delete_button)

        self.select_all_button = Gtk.Button(label="전체 선택", sensitive=False)
        self.select_all_button.connect("clicked", self._select_all)
        action_bar.append(self.select_all_button)

        self.clear_selection_button = Gtk.Button(label="선택 해제", sensitive=False)
        self.clear_selection_button.connect("clicked", self._clear_selection)
        action_bar.append(self.clear_selection_button)

        self.search_entry = Gtk.SearchEntry(placeholder_text="현재 폴더 검색")
        self.search_entry.set_hexpand(True)
        self.search_entry.connect("search-changed", self._filter_entries)
        action_bar.append(self.search_entry)

        scroller = Gtk.ScrolledWindow(vexpand=True)
        root.append(scroller)

        list_area = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        scroller.set_child(list_area)

        header = Gtk.Box(spacing=10)
        header.set_margin_start(10)
        header.set_margin_end(10)
        name_header = Gtk.Label(label="이름", xalign=0, hexpand=True)
        name_header.add_css_class("heading")
        header.append(name_header)
        size_header = Gtk.Label(label="용량", xalign=1)
        size_header.set_width_chars(11)
        size_header.add_css_class("heading")
        header.append(size_header)
        list_area.append(header)

        self.file_list = Gtk.ListBox(selection_mode=Gtk.SelectionMode.SINGLE)
        self.file_list.add_css_class("boxed-list")
        self.file_list.connect("row-activated", self._activate_row)
        self.file_list.connect("selected-rows-changed", self._selection_changed)
        list_area.append(self.file_list)

        self.status_label = Gtk.Label(xalign=0, wrap=True)
        self.status_label.add_css_class("dim-label")
        root.append(self.status_label)

    def _open_location(self, *_args: object) -> None:
        assert self.location_entry is not None
        location = self.location_entry.get_text().strip()
        if not location:
            return
        file = Gio.File.new_for_uri(location) if "://" in location else Gio.File.new_for_path(location)
        self._open_file(file, add_history=True)

    def _open_file(self, file: Gio.File, add_history: bool) -> None:
        try:
            info = file.query_info("standard::type", Gio.FileQueryInfoFlags.NONE, None)
            if info.get_file_type() != Gio.FileType.DIRECTORY:
                self._set_status("폴더만 열 수 있습니다.")
                return
            self.current_file = file
            uri = file.get_uri()
            if add_history:
                self.history = self.history[: self.history_index + 1]
                self.history.append(uri)
                self.history_index += 1
            self._refresh()
        except Exception as error:
            self._set_status(f"위치를 열 수 없습니다: {error}")

    def _refresh(self) -> None:
        assert self.file_list is not None
        assert self.location_entry is not None
        while (row := self.file_list.get_first_child()) is not None:
            self.file_list.remove(row)

        try:
            enumerator = self.current_file.enumerate_children(
                "standard::name,standard::display-name,standard::type,standard::icon,standard::size,standard::target-uri",
                Gio.FileQueryInfoFlags.NONE,
                None,
            )
            entries: list[tuple[Gio.File, Gio.FileInfo]] = []
            while (info := enumerator.next_file(None)) is not None:
                entries.append((self.current_file.get_child(info.get_name()), info))
            enumerator.close(None)
            # 폴더는 항상 먼저 두고, 각 그룹 안에서만 이름 방향을 적용한다.
            directories = [entry for entry in entries if entry[1].get_file_type() == Gio.FileType.DIRECTORY]
            files = [entry for entry in entries if entry[1].get_file_type() != Gio.FileType.DIRECTORY]
            directories.sort(key=lambda entry: natural_name_key(entry[1].get_display_name()), reverse=self.descending)
            files.sort(key=lambda entry: natural_name_key(entry[1].get_display_name()), reverse=self.descending)
            entries = directories + files
            self.entries = entries
            self._render_entries()
            self.location_entry.set_text(self.current_file.get_uri())
            self._set_status(f"{len(entries)}개 항목 · 네트워크 탐색에서 NAS와 공유 폴더를 선택하세요.")
            self._update_navigation()
        except Exception as error:
            self._set_status(f"폴더 내용을 읽을 수 없습니다: {error}")

    def _make_row(self, file: Gio.File, info: Gio.FileInfo) -> Gtk.ListBoxRow:
        row = Gtk.ListBoxRow()
        row.file = file
        row.info = info
        box = Gtk.Box(spacing=10)
        box.set_margin_top(8)
        box.set_margin_bottom(8)
        box.set_margin_start(10)
        box.set_margin_end(10)
        icon = Gtk.Image.new_from_gicon(info.get_icon())
        icon.set_pixel_size(24)
        box.append(icon)
        label = Gtk.Label(label=info.get_display_name(), xalign=0, hexpand=True)
        label.set_ellipsize(3)
        box.append(label)
        size = "—" if info.get_file_type() == Gio.FileType.DIRECTORY else format_size(info.get_size())
        size_label = Gtk.Label(label=size, xalign=1)
        size_label.set_width_chars(11)
        size_label.add_css_class("dim-label")
        box.append(size_label)
        row.set_child(box)
        return row

    def _render_entries(self) -> None:
        """검색어에 맞는 현재 폴더 항목만 목록에 그린다."""
        assert self.file_list is not None and self.search_entry is not None
        while (row := self.file_list.get_first_child()) is not None:
            self.file_list.remove(row)
        query = self.search_entry.get_text().strip().casefold()
        filtered = [entry for entry in self.entries if query in entry[1].get_display_name().casefold()]
        for child, info in filtered:
            self.file_list.append(self._make_row(child, info))
        self._selection_changed(self.file_list)

    def _filter_entries(self, *_args: object) -> None:
        self._render_entries()

    def _select_all(self, *_args: object) -> None:
        assert self.file_list is not None
        self.file_list.select_all()

    def _clear_selection(self, *_args: object) -> None:
        assert self.file_list is not None
        self.file_list.unselect_all()

    def _activate_row(self, _list_box: Gtk.ListBox, row: Gtk.ListBoxRow) -> None:
        if row.file.get_uri_scheme() == "network":
            target_uri = row.info.get_attribute_string("standard::target-uri")
            if target_uri:
                self._open_file(Gio.File.new_for_uri(target_uri), add_history=True)
            else:
                self._open_file(row.file, add_history=True)
            return
        if row.info.get_file_type() == Gio.FileType.DIRECTORY:
            self._open_file(row.file, add_history=True)
        else:
            try:
                Gio.AppInfo.launch_default_for_uri(row.file.get_uri(), None)
            except Exception as error:
                self._set_status(f"파일을 열 수 없습니다: {error}")

    def _selection_changed(self, list_box: Gtk.ListBox) -> None:
        assert self.rename_button is not None and self.delete_button is not None
        has_selection = self.multi_select_enabled and bool(list_box.get_selected_rows())
        self.rename_button.set_sensitive(has_selection)
        self.delete_button.set_sensitive(has_selection)

    def _toggle_selection_mode(self, button: Gtk.ToggleButton) -> None:
        """선택 모드에서만 다중 선택 및 일괄 작업을 허용한다."""
        assert self.file_list is not None
        assert self.select_all_button is not None and self.clear_selection_button is not None
        self.multi_select_enabled = button.get_active()
        mode = Gtk.SelectionMode.MULTIPLE if self.multi_select_enabled else Gtk.SelectionMode.SINGLE
        self.file_list.set_selection_mode(mode)
        self.file_list.unselect_all()
        self.select_all_button.set_sensitive(self.multi_select_enabled)
        self.clear_selection_button.set_sensitive(self.multi_select_enabled)
        self._selection_changed(self.file_list)

    def _confirm_delete_selected(self, *_args: object) -> None:
        """로컬은 휴지통으로, SMB NAS는 영구 삭제로 처리할지 확인한다."""
        assert self.window is not None and self.file_list is not None
        rows = self.file_list.get_selected_rows()
        if not rows:
            return
        nas_count = sum(row.file.get_uri_scheme() == "smb" for row in rows)
        local_count = len(rows) - nas_count
        dialog = Gtk.Dialog(title="선택 항목 삭제", transient_for=self.window, modal=True)
        dialog.add_button("취소", Gtk.ResponseType.CANCEL)
        dialog.add_button("삭제", Gtk.ResponseType.ACCEPT).add_css_class("destructive-action")
        content = dialog.get_content_area()
        content.set_margin_top(12)
        content.set_margin_bottom(12)
        content.set_margin_start(12)
        content.set_margin_end(12)
        message = f"선택한 {len(rows)}개 항목을 삭제할까요?"
        if nas_count:
            message += f"\nSMB/NAS 항목 {nas_count}개는 휴지통을 거치지 않고 영구 삭제됩니다."
        if local_count:
            message += f"\n로컬 항목 {local_count}개는 휴지통으로 이동합니다."
        content.append(Gtk.Label(label=message, xalign=0, wrap=True))
        dialog.connect("response", self._delete_response, rows)
        dialog.present()

    def _delete_response(self, dialog: Gtk.Dialog, response: int, rows: list[Gtk.ListBoxRow]) -> None:
        if response != Gtk.ResponseType.ACCEPT:
            dialog.destroy()
            return
        trashed = 0
        deleted = 0
        skipped: list[str] = []
        for row in rows:
            try:
                if row.file.get_uri_scheme() == "smb":
                    row.file.delete(None)
                    deleted += 1
                else:
                    row.file.trash(None)
                    trashed += 1
            except Exception as error:
                skipped.append(f"{row.file.get_basename()}: {error}")
        report_parts: list[str] = []
        if deleted:
            report_parts.append(f"SMB/NAS {deleted}개를 영구 삭제했습니다.")
        if trashed:
            report_parts.append(f"로컬 {trashed}개를 휴지통으로 이동했습니다.")
        report = " ".join(report_parts) or "삭제한 항목이 없습니다."
        if skipped:
            report += f" {len(skipped)}개 처리하지 못함: " + "; ".join(skipped[:5])
            if len(skipped) > 5:
                report += f" 외 {len(skipped) - 5}개"
        self._set_status(report)
        self._refresh()
        dialog.destroy()

    def _show_rename_dialog(self, *_args: object) -> None:
        """선택 항목의 새 이름을 확인한 뒤 일괄 변경 대화 상자를 연다."""
        assert self.window is not None and self.file_list is not None
        rows = self.file_list.get_selected_rows()
        if not rows:
            return

        dialog = Gtk.Dialog(title="선택 항목 이름 일괄 변경", transient_for=self.window, modal=True)
        dialog.add_button("취소", Gtk.ResponseType.CANCEL)
        apply_button = dialog.add_button("적용", Gtk.ResponseType.APPLY)
        apply_button.add_css_class("suggested-action")
        content = dialog.get_content_area()
        content.set_spacing(8)
        content.set_margin_top(12)
        content.set_margin_bottom(12)
        content.set_margin_start(12)
        content.set_margin_end(12)

        grid = Gtk.Grid(column_spacing=8, row_spacing=8)
        content.append(grid)
        prefix = Gtk.Entry(placeholder_text="접두사")
        find = Gtk.Entry(placeholder_text="찾을 문자열")
        replace = Gtk.Entry(placeholder_text="바꿀 문자열")
        suffix = Gtk.Entry(placeholder_text="접미사")
        add_number = Gtk.CheckButton(label="끝에 번호 붙이기")
        start = Gtk.SpinButton.new_with_range(1, 999999, 1)
        digits = Gtk.SpinButton.new_with_range(1, 9, 1)
        digits.set_value(3)
        fields = (("접두사", prefix), ("찾기", find), ("바꾸기", replace), ("접미사", suffix),
                  ("시작 번호", start), ("번호 자릿수", digits))
        for index, (label, field) in enumerate(fields):
            grid.attach(Gtk.Label(label=label, xalign=0), 0, index, 1, 1)
            grid.attach(field, 1, index, 1, 1)
        grid.attach(add_number, 1, len(fields), 1, 1)

        preview = Gtk.Label(xalign=0, wrap=True, selectable=True)
        preview.set_margin_top(8)
        content.append(preview)

        def refresh_preview(*_ignored: object) -> None:
            plan, skipped, error = self._rename_plan(rows, prefix.get_text(), find.get_text(), replace.get_text(),
                                                     suffix.get_text(), add_number.get_active(), start.get_value_as_int(),
                                                     digits.get_value_as_int())
            if error:
                preview.set_text(f"적용할 수 없습니다: {error}")
                apply_button.set_sensitive(False)
                return
            examples = [f"{source.get_basename()}  →  {target}" for source, target in plan[:5]]
            more = "" if len(plan) <= 5 else f"\n… 외 {len(plan) - 5}개"
            skipped_note = "" if not skipped else f"\n건너뜀 예정: {len(skipped)}개\n" + "\n".join(skipped[:3])
            preview.set_text("미리보기\n" + "\n".join(examples) + more + skipped_note)
            apply_button.set_sensitive(True)

        for field in (prefix, find, replace, suffix):
            field.connect("changed", refresh_preview)
        for field in (add_number, start, digits):
            field.connect("notify::active" if field is add_number else "value-changed", refresh_preview)
        refresh_preview()
        dialog.connect("response", self._rename_response, rows, prefix, find, replace, suffix, add_number, start, digits)
        dialog.present()

    def _rename_plan(self, rows: list[Gtk.ListBoxRow], prefix: str, find: str, replace: str, suffix: str,
                     add_number: bool, start: int, digits: int) -> tuple[list[tuple[Gio.File, str]], list[str], str | None]:
        """이름 변경 대상과 충돌 여부를 먼저 계산한다."""
        plan: list[tuple[Gio.File, str]] = []
        skipped: list[str] = []
        names: set[str] = set()
        sources = {row.file.get_basename() for row in rows}
        for index, row in enumerate(rows):
            old_name = row.file.get_basename()
            stem, dot, extension = old_name.rpartition(".")
            if not dot or not stem:
                stem, extension = old_name, ""
            replaced_stem = stem.replace(find, replace) if find else stem
            new_stem = prefix + replaced_stem + suffix
            number = f"{start + index:0{digits}d}" if add_number else ""
            new_name = f"{new_stem}{number}{dot}{extension}" if extension else f"{new_stem}{number}"
            if not new_name or "/" in new_name or new_name in {".", ".."}:
                return [], [], f"유효하지 않은 파일 이름: {new_name!r}"
            if new_name in names:
                skipped.append(f"{old_name}: 변경 결과 중복({new_name})")
                continue
            if new_name != old_name and new_name in sources:
                skipped.append(f"{old_name}: 선택 항목과 이름 충돌({new_name})")
                continue
            names.add(new_name)
            plan.append((row.file, new_name))
        return plan, skipped, None

    def _rename_response(self, dialog: Gtk.Dialog, response: int, rows: list[Gtk.ListBoxRow], prefix: Gtk.Entry,
                         find: Gtk.Entry, replace: Gtk.Entry, suffix: Gtk.Entry, add_number: Gtk.CheckButton,
                         start: Gtk.SpinButton, digits: Gtk.SpinButton) -> None:
        if response != Gtk.ResponseType.APPLY:
            dialog.destroy()
            return
        plan, skipped, error = self._rename_plan(rows, prefix.get_text(), find.get_text(), replace.get_text(), suffix.get_text(),
                                                 add_number.get_active(), start.get_value_as_int(), digits.get_value_as_int())
        if error:
            self._set_status(f"이름 변경을 취소했습니다: {error}")
            dialog.destroy()
            return
        changed = 0
        for source, target_name in plan:
            if source.get_basename() == target_name:
                continue
            try:
                destination = source.get_parent().get_child(target_name)
                if destination.query_exists(None):
                    skipped.append(f"{source.get_basename()}: 같은 이름이 이미 존재함({target_name})")
                    continue
                if source.get_basename() != target_name:
                    source.move(source.get_parent().get_child(target_name), Gio.FileCopyFlags.NONE, None, None, None)
                    changed += 1
            except Exception as error:
                skipped.append(f"{source.get_basename()}: 변경 실패({error})")
        report = f"{changed}개 항목의 이름을 변경했습니다."
        if skipped:
            report += f" {len(skipped)}개 건너뜀: " + "; ".join(skipped[:5])
            if len(skipped) > 5:
                report += f" 외 {len(skipped) - 5}개"
        self._set_status(report)
        self._refresh()
        dialog.destroy()

    def _go_back(self, *_args: object) -> None:
        if self.history_index > 0:
            self.history_index -= 1
            self._open_file(Gio.File.new_for_uri(self.history[self.history_index]), add_history=False)

    def _go_forward(self, *_args: object) -> None:
        if self.history_index + 1 < len(self.history):
            self.history_index += 1
            self._open_file(Gio.File.new_for_uri(self.history[self.history_index]), add_history=False)

    def _go_up(self, *_args: object) -> None:
        parent = self.current_file.get_parent()
        if parent is not None:
            self._open_file(parent, add_history=True)

    def _go_home(self, *_args: object) -> None:
        self._open_file(Gio.File.new_for_path(os.path.expanduser("~")), add_history=True)

    def _browse_network(self, *_args: object) -> None:
        """GVFS가 발견한 네트워크 위치를 파일 목록으로 연다."""
        self._open_file(Gio.File.new_for_uri("network:///"), add_history=True)

    def _browse_smb(self, *_args: object) -> None:
        """GVFS 네트워크 탐색기를 열어 SMB/NAS를 목록에서 고르게 한다."""
        self._browse_network()

    def _toggle_sort(self, *_args: object) -> None:
        self.descending = not self.descending
        self.sort_button.set_label("이름: 내림차순" if self.descending else "이름: 오름차순")
        self._refresh()

    def _update_navigation(self) -> None:
        assert self.back_button is not None and self.forward_button is not None
        self.back_button.set_sensitive(self.history_index > 0)
        self.forward_button.set_sensitive(self.history_index + 1 < len(self.history))

    def _set_status(self, message: str) -> None:
        assert self.status_label is not None
        self.status_label.set_text(message)


if __name__ == "__main__":
    raise SystemExit(FileExplorer().run(sys.argv))
