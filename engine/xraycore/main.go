// SilentGate — ядро Xray для Windows-сборки Microsoft Store.
// Copyright (C) 2026 SilentGate contributors. Лицензия — GPL-3.0 (см. LICENSE в корне).
//
// Зачем своя программа, а не официальный xray.exe. Store требует подписи у
// каждого PE-файла поставки, а бесплатная подпись SignPath Foundation
// подписывает только то, что собрано из исходников самого проекта: чужой
// готовый xray.exe ею подписывать нельзя. Поэтому ядро собирается в нашем CI
// из этого файла, а Xray-core (MPL-2.0) подключается как обычная библиотека
// Go — так же, как его подключает libXray на Android.
//
// Приложение зовёт ядро ровно так же, как официальное, и разницы не видит:
//
//	xray run -c <config.json>          — поднять ядро (engine/windows/xray_process.dart)
//	xray run -test -c <config.json>    — только проверить конфиг (tool/, docs)
//	xray version                       — «Xray X.Y.Z …» (engine/windows/xray_version.dart)
//	xray api statsquery|bi …           — счётчики и балансировщик (xray_stats.dart)
//
// Команды api/tls/uuid/x25519 и прочие регистрирует сам Xray-core
// (main/commands/all, его подтягивает main/distro/all). Свои здесь только run
// и version: в Xray-core они живут в пакете main и как библиотека недоступны.
package main

import (
	"fmt"
	"os"
	"os/signal"
	"runtime"
	"runtime/debug"
	"syscall"

	"github.com/xtls/xray-core/common/cmdarg"
	"github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/main/commands/base"
	_ "github.com/xtls/xray-core/main/distro/all"
)

// Код выхода при ошибке конфига — тот же, что у официального ядра.
const exitBadConfig = 23

var cmdRun = &base.Command{
	UsageLine: "{{.Exec}} run [-test] [-format json] -c config.json",
	Short:     "Run Xray with config",
	Long: `
Run Xray with config.

The -config=file, -c=file flags set the config files. Multiple assign is
accepted. "stdin:" reads the config from standard input.

The -format=json flag sets the format of config files. Default "auto".

The -test flag only tests config files, without launching the server.
	`,
}

var cmdVersion = &base.Command{
	UsageLine: "{{.Exec}} version",
	Short:     "Show current version of Xray",
	Long:      "Version prints the build information for Xray executables.",
	Run:       func(*base.Command, []string) { printVersion() },
}

var (
	configFiles cmdarg.Arg
	testOnly    = cmdRun.Flag.Bool("test", false, "Test config files only, without launching the server.")
	format      = cmdRun.Flag.String("format", "auto", "Format of input files.")
)

func init() {
	cmdRun.Run = executeRun // иначе цикл инициализации: executeRun ссылается на cmdRun
	cmdRun.Flag.Var(&configFiles, "config", "Config path for Xray.")
	cmdRun.Flag.Var(&configFiles, "c", "Short alias of -config")
}

func main() {
	base.RootCommand.Long = "Xray core built for SilentGate."
	base.RootCommand.Commands = append(
		[]*base.Command{cmdRun, cmdVersion},
		base.RootCommand.Commands...,
	)
	base.Execute()
}

func printVersion() {
	for _, s := range core.VersionStatement() {
		fmt.Println(s)
	}
}

func executeRun(_ *base.Command, _ []string) {
	printVersion()
	server, err := loadServer()
	if err != nil {
		fmt.Println("Failed to start:", err)
		os.Exit(exitBadConfig)
	}
	if *testOnly {
		fmt.Println("Configuration OK.")
		os.Exit(0)
	}
	if err := server.Start(); err != nil {
		fmt.Println("Failed to start:", err)
		os.Exit(1)
	}
	defer server.Close()

	// Разбор конфига оставляет много мусора — отдаём память сразу, как и
	// официальное ядро: процесс живёт всю сессию VPN.
	runtime.GC()
	debug.FreeOSMemory()

	sig := make(chan os.Signal, 1)
	signal.Notify(sig, os.Interrupt, syscall.SIGTERM)
	<-sig
}

// loadServer читает конфиг и создаёт сервер, не запуская его. Без -c ядро
// читает конфиг со стандартного ввода — поиск config.json в рабочем каталоге
// и по переменным окружения (как у официального ядра) намеренно не делается:
// приложение всегда передаёт путь явно, а подхват чужого файла был бы сюрпризом.
func loadServer() (core.Server, error) {
	files := configFiles
	if len(files) == 0 {
		files = cmdarg.Arg{"stdin:"}
	}
	f := core.GetFormatByExtension(*format)
	if f == "" {
		f = "auto"
	}
	c, err := core.LoadConfig(f, files)
	if err != nil {
		return nil, fmt.Errorf("failed to load config files: [%s]: %w", files.String(), err)
	}
	server, err := core.New(c)
	if err != nil {
		return nil, fmt.Errorf("failed to create server: %w", err)
	}
	return server, nil
}
