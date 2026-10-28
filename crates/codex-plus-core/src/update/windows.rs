//! Windows 单文件更新：同卷暂存，等待主进程退出后替换，失败恢复原文件。
use std::os::windows::process::CommandExt;
use std::path::Path;

use anyhow::{Context, ensure};

const HELPER: &str = include_str!("windows-update.ps1");

pub fn launch_update(download: &Path) -> anyhow::Result<()> {
    let bytes = std::fs::read(download).context("读取单文件更新失败")?;
    validate_executable(&bytes)?;
    let target = std::env::current_exe()?;
    let parent = target.parent().context("无法确定当前程序目录")?;
    let transaction = parent.join(format!(".codexpp-update-{}", uuid::Uuid::new_v4()));
    std::fs::create_dir(&transaction)
        .context("程序目录不可写，请将单文件版放到有写权限的目录后更新")?;
    let staged = transaction.join("new.exe");
    std::fs::write(&staged, &bytes)?;
    let script = transaction.join("update.ps1");
    // Windows PowerShell 5.1 需要 BOM 才能正确识别 UTF-8。
    std::fs::write(&script, format!("\u{feff}{HELPER}"))?;
    let mut helper = std::process::Command::new("powershell.exe")
        .args([
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
        ])
        .arg(&script)
        .env("CODEX_PLUS_UPDATE_TARGET", &target)
        .env("CODEX_PLUS_UPDATE_TRANSACTION", &transaction)
        .env("CODEX_PLUS_UPDATE_PID", std::process::id().to_string())
        .creation_flags(crate::windows_integration::CREATE_NO_WINDOW)
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn()
        .context("启动单文件更新助手失败")?;
    // 助手确认启动后才允许 UI 退出，避免策略限制或脚本错误导致程序直接关闭。
    for _ in 0..100 {
        if transaction.join("ready").exists() {
            return Ok(());
        }
        if let Some(status) = helper.try_wait()? {
            anyhow::bail!(
                "更新助手提前退出（{status}），详见 {}",
                transaction.display()
            );
        }
        std::thread::sleep(std::time::Duration::from_millis(100));
    }
    let _ = helper.kill();
    anyhow::bail!(
        "更新助手未就绪，保留当前版本；详见 {}",
        transaction.display()
    )
}

fn validate_executable(bytes: &[u8]) -> anyhow::Result<()> {
    ensure!(
        bytes.len() >= 64 && &bytes[..2] == b"MZ",
        "更新文件不是 Windows 可执行程序"
    );
    let offset = u32::from_le_bytes(bytes[60..64].try_into().unwrap()) as usize;
    let header = bytes
        .get(offset..offset.saturating_add(26))
        .context("更新文件 PE 头不完整")?;
    ensure!(
        &header[..4] == b"PE\0\0" && header[4..6] == [0x64, 0x86] && header[24..26] == [0x0b, 0x02],
        "更新文件不是 x64 PE 程序"
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_html_truncation_and_wrong_architecture() {
        assert!(validate_executable(b"<html>download failed</html>").is_err());
        let mut pe = vec![0; 128];
        pe[..2].copy_from_slice(b"MZ");
        pe[60..64].copy_from_slice(&64_u32.to_le_bytes());
        pe[64..70].copy_from_slice(b"PE\0\0\x64\x86");
        pe[88..90].copy_from_slice(&[0x0b, 0x02]);
        assert!(validate_executable(&pe).is_ok());
        pe[68] = 0x4c;
        assert!(validate_executable(&pe).is_err());
        assert!(validate_executable(&pe[..80]).is_err());
    }
}
