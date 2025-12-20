const std = @import("std");
const builtin = @import("builtin");
const win32 = @import("win32").everything;

pub const Flags = struct {
    icon: Icon = .info,
    modal: bool = true,

    pub const Icon = enum {
        info,
        warning,
        @"error",
        question,

        fn toWin32(self: @This()) win32.MESSAGEBOX_STYLE {
            return switch (self) {
                .info => win32.MB_ICONINFORMATION,
                .warning => win32.MB_ICONWARNING,
                .@"error" => win32.MB_ICONERROR,
                .question => win32.MB_ICONQUESTION,
            };
        }

        pub fn toZenity(self: @This()) []const u8 {
            return switch (self) {
                .info => "--info",
                .warning => "--warning",
                .@"error" => "--error",
                .question => "--question",
            };
        }
    };

    fn toWin32(self: @This()) win32.MESSAGEBOX_STYLE {
        var flags: win32.MESSAGEBOX_STYLE = self.icon.toWin32();

        if (self.modal) flags.TASKMODAL = 1;
        flags.YESNO = 1;

        return flags;
    }
};

pub fn open(allocator: std.mem.Allocator, title: []const u8, text: []const u8, flags: Flags) !void {
    switch (builtin.os.tag) {
        .windows => {
            const title16 = try std.unicode.utf8ToUtf16LeAllocZ(allocator, title);
            defer allocator.free(title16);

            const text16 = try std.unicode.utf8ToUtf16LeAllocZ(allocator, text);
            defer allocator.free(text16);

            _ = win32.MessageBoxW(null, @ptrCast(text16), @ptrCast(title16), flags.toWin32());
        },
        else => {
            // Best-effort: don't fail the program if zenity is missing
            var child = std.process.Child.init(
                &[_][]const u8{
                    "zenity",
                    flags.icon.toZenity(),
                    "--title",
                    title,
                    "--text",
                    text,
                },
                allocator,
            );
            _ = try child.spawnAndWait();
        },
    }
}
