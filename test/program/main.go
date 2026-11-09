// Command program is the Pulumi program the integration tests run. It exports
// everything the tests check: config (plain and secret), its working
// directory, a data file read by relative path, a provider resource, and the
// environment variables the env precedence tests set.
package main

import (
	"os"
	"strings"

	"github.com/pulumi/pulumi-random/sdk/v4/go/random"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := config.New(ctx, "")
		ctx.Export("greeting", pulumi.String(cfg.Require("greeting")))
		ctx.Export("token", cfg.RequireSecret("token"))

		wd, err := os.Getwd()
		if err != nil {
			return err
		}
		ctx.Export("cwd", pulumi.String(wd))

		data, err := os.ReadFile("testdata/hello.txt")
		if err != nil {
			return err
		}
		ctx.Export("data", pulumi.String(strings.TrimSpace(string(data))))

		for _, k := range []string{"PROBE_ENV", "PROBE_CMD", "PROBE_CMDS", "PROBE_SHELL_ENV", "PROBE_SHELL_CMD", "RUNFILES_DIR"} {
			ctx.Export(k, pulumi.String(os.Getenv(k)))
		}

		if cfg.GetBool("pet") {
			pet, err := random.NewRandomPet(ctx, "pet", &random.RandomPetArgs{})
			if err != nil {
				return err
			}
			ctx.Export("pet", pet.ID())
		}
		return nil
	})
}
