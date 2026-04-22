package cmd

import (
	"fmt"

	log "github.com/sirupsen/logrus"

	_ "github.com/InazumaV/V2bX/core/imports"
	"github.com/spf13/cobra"
)

const zhUsageTemplate = `{{if .Runnable}}用法:
  {{.UseLine}}{{end}}{{if .HasAvailableSubCommands}}用法:
  {{.CommandPath}} [命令]{{end}}{{if gt (len .Aliases) 0}}

别名:
  {{.NameAndAliases}}{{end}}{{if .HasExample}}

示例:
{{.Example}}{{end}}{{if .HasAvailableSubCommands}}

可用命令:{{range .Commands}}{{if (or .IsAvailableCommand (eq .Name "help"))}}
  {{rpad .Name .NamePadding }} {{.Short}}{{end}}{{end}}{{end}}{{if .HasAvailableLocalFlags}}

选项:
{{.LocalFlags.FlagUsages | trimTrailingWhitespaces}}{{end}}{{if .HasAvailableInheritedFlags}}

全局选项:
{{.InheritedFlags.FlagUsages | trimTrailingWhitespaces}}{{end}}{{if .HasHelpSubCommands}}

更多帮助主题:{{range .Commands}}{{if .IsAdditionalHelpTopicCommand}}
  {{rpad .CommandPath .CommandPathPadding}} {{.Short}}{{end}}{{end}}{{end}}{{if .HasAvailableSubCommands}}

使用 "{{.CommandPath}} [命令] --help" 查看更多信息。{{end}}
`

var command = &cobra.Command{
	Use: "V2bX",
}

func init() {
	command.SetUsageTemplate(zhUsageTemplate)
	command.SetHelpTemplate(`{{if .Long}}{{.Long | trimTrailingWhitespaces}}

{{end}}{{.UsageString}}`)
	command.PersistentFlags().BoolP("help", "h", false, "显示帮助")
	command.SetHelpCommand(&cobra.Command{
		Use:   "help [命令]",
		Short: "显示命令帮助",
		Args:  cobra.MaximumNArgs(1),
		Run: func(_ *cobra.Command, args []string) {
			target := command.Root()
			if len(args) > 0 {
				var err error
				target, _, err = command.Root().Find(args)
				if err != nil || target == nil {
					fmt.Printf("未找到命令: %s\n", args[0])
					return
				}
			}
			_ = target.Help()
		},
	})
}

func Run() {
	localizeBuiltinCommands()
	err := command.Execute()
	if err != nil {
		log.WithField("err", err).Error("Execute command failed")
	}
}

func localizeBuiltinCommands() {
	command.InitDefaultCompletionCmd()
	for _, sub := range command.Commands() {
		if sub.Name() == "completion" {
			sub.Short = "生成自动补全脚本"
			sub.Long = "为指定 Shell 生成自动补全脚本"
			break
		}
	}
}
