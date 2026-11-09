"""Public API of rules_pulumi."""

load("//pulumi/private:project.bzl", _PulumiProjectInfo = "PulumiProjectInfo", _pulumi_project = "pulumi_project")
load("//pulumi/private:provider.bzl", _PulumiProviderInfo = "PulumiProviderInfo", _pulumi_provider = "pulumi_provider")
load("//pulumi/private:stack.bzl", _pulumi_stack = "pulumi_stack", _pulumi_stack_reference = "pulumi_stack_reference", _pulumi_stack_rule = "pulumi_stack_rule")

pulumi_project = _pulumi_project
pulumi_stack = _pulumi_stack
pulumi_stack_rule = _pulumi_stack_rule
pulumi_stack_reference = _pulumi_stack_reference
pulumi_provider = _pulumi_provider
PulumiProjectInfo = _PulumiProjectInfo
PulumiProviderInfo = _PulumiProviderInfo
