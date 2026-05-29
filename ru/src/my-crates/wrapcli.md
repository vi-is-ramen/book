# `wrapcli`: Легко подделывайте идентичность командной строки

**wrapcli** — это библиотека Rust, которая оборачивает существующий инструмент командной строки и переписывает его вывод на лету, делая так, чтобы выглядело, будто вывод был создан другим инструментом.

### Возможности

- Потоковое переписывание вывода в реальном времени (строка за строкой)
- Захват полного вывода для постобработки
- Настраиваемые правила переписывания
- Опциональное сохранение оригинальной информации о версии

### Варианты использования

- Создание брендированных вариантов CLI-инструментов
- Маскировка внутренних имён инструментов в выводе, видимом пользователю
- Добавление информации о версии без изменения нижележащего инструмента
- Интеграция устаревших инструментов в современные рабочие процессы

## Начало работы

### Установка

Добавьте `wrapcli` в ваши зависимости:

```shell
cargo add wrapcli
```

### Базовое использование

```rust
use wrapcli::{run_streaming, WrapConfig};

fn main() -> std::io::Result<()> {
    let cfg = WrapConfig {
        orig_name: "rustc".into(),
        fake_name: "dustc".into(),
        fake_ver: "2.0.0".into(),
        save_orig: true,
    };

    let args: Vec<String> = std::env::args().skip(1).collect();
    let status = run_streaming(&cfg, args)?;
    std::process::exit(status.code().unwrap_or(1));
}
```

## Как это работает

Когда обёрнутый инструмент выводит строку, содержащую оригинальное имя, `wrapcli` перехватывает её и применяет правила переписывания:

1. **Первое вхождение** оригинального имени и версии инструмента заменяется на поддельное имя и поддельную версию. Если `save_orig` равно `true`, оригинальная версия добавляется в скобках.
2. Любые **последующие вхождения** оригинального имени в строках использования заменяются на поддельное имя.

Это обеспечивает согласованное маскирование вывода без нарушения функциональности инструмента.

## Конфигурация

Структура `WrapConfig` управляет поведением переписывания.

### Поля

| Поле | Тип | Описание |
|------|------|-------------|
| `orig_name` | `String` | Оригинальное имя инструмента (например, `"rustc"`) |
| `fake_name` | `String` | Имя, которое будет отображаться вместо него (например, `"dustc"`) |
| `fake_ver` | `String` | Строка версии для отображения (например, `"2.0.0"`) |
| `save_orig` | `bool` | Нужно ли добавлять оригинальную версию в скобках |

### Пример

```rust
use wrapcli::WrapConfig;

let cfg = WrapConfig {
    orig_name: "git".into(),
    fake_name: "gitter".into(),
    fake_ver: "3.0.0".into(),
    save_orig: false,
};
```

## Примеры

### Потоковый вывод

```rust
use wrapcli::{run_streaming, WrapConfig};

fn main() -> std::io::Result<()> {
    let cfg = WrapConfig {
        orig_name: "cargo".into(),
        fake_name: "pargo".into(),
        fake_ver: "2.0.0".into(),
        save_orig: true,
    };

    let args = vec!["--version".to_string()];
    run_streaming(&cfg, args)?;
    Ok(())
}
```

### Захват вывода

```rust
use wrapcli::{run_capture, WrapConfig};

fn main() -> std::io::Result<()> {
    let cfg = WrapConfig {
        orig_name: "rustc".into(),
        fake_name: "dustc".into(),
        fake_ver: "2.0.0".into(),
        save_orig: false,
    };

    let args = vec!["--version".to_string()];
    let result = run_capture(&cfg, args)?;
    
    println!("Захваченный stdout: {}", String::from_utf8_lossy(&result.stdout));
    println!("Захваченный stderr: {}", String::from_utf8_lossy(&result.stderr));
    Ok(())
}
```

### Реальный пример: обёртка для Git

```rust
use wrapcli::{run_streaming, WrapConfig};
use std::env;

fn main() -> std::io::Result<()> {
    let cfg = WrapConfig {
        orig_name: "git".into(),
        fake_name: "gitter".into(),
        fake_ver: "3.0.0".into(),
        save_orig: true,
    };

    let args: Vec<String> = env::args().skip(1).collect();
    run_streaming(&cfg, args)
}
```

## Ссылки

[crates.io](https://crates.io/wrapcli)
[docs.rs](https://docs.rs/wrapcli)
