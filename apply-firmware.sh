#!/bin/bash
## Copyright (c) Microsoft Corporation.
## Licensed under the MIT License.

# unlock HP NIC firmware

mlxconfig -d mlx5_0 apply ~/firmware/HPE0000000014-16.26.1040-2020-04-16T20_55_22.789336.support.token.bin
mlxconfig -d mlx5_0 apply ~/firmware/HPE0000000014-16.26.1040-2020-04-16T20_56_10.596387.support.token.bin
