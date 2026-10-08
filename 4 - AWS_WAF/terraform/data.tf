###############################################################################
# Data Sources
###############################################################################

# Current AWS Account
data "aws_caller_identity" "current" {}

# Current AWS Region
data "aws_region" "current" {}
