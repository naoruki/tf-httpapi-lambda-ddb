data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/package"
  output_path = "${path.module}/package.zip"
}

resource "aws_lambda_function" "http_api_lambda" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${local.name_prefix}-topmovies-api"
  description      = "Lambda function to write to dynamodb"
  runtime          = "python3.13"
  handler          = "app.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  role             = aws_iam_role.lambda_exec.arn

  environment {
    variables = {
      DDB_TABLE = aws_dynamodb_table.table.name
    }
  }

  # depends_on = [ aws_cloudwatch_log_group.http_api ]
}

# resource "aws_cloudwatch_log_group" "http_api" {
#   name              = "/aws/lambda/${local.name_prefix}-topmovies-api"
#   retention_in_days = 7
# }

resource "aws_iam_role" "lambda_exec" {
  name = "${local.name_prefix}-topmovies-api-executionrole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Sid    = ""
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_exec_role" {
  name = "${local.name_prefix}-topmovies-api-ddbaccess"

  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:GetItem",
                "dynamodb:PutItem",
                "dynamodb:DeleteItem",
                "dynamodb:Scan"
            ],
            "Resource": "${aws_dynamodb_table.table.arn}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "xray:PutTraceSegments",
                "xray:PutTelemetryRecords"
            ],
            "Resource": "*"
        }
    ]
}
POLICY
}

resource "aws_cloudwatch_metric_alarm" "lambda_error_alarm" {
  alarm_name          = "LambdaErrorAlarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors" # Lambda metric for errors
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 1

  alarm_description   = "Alarm when Lambda function errors exceed the threshold"
  alarm_actions       = [aws_sns_topic.lambda_alarm_topic.arn] # SNS Topic ARN
  ok_actions          = [aws_sns_topic.lambda_alarm_topic.arn] # SNS Topic ARN
  dimensions = {
    FunctionName = "http_api_lambda" # Replace with your Lambda function name
  }
}

resource "aws_sns_topic" "lambda_alarm_topic" {
  name = "LambdaAlarmTopic"
}

resource "aws_sns_topic_subscription" "lambda_alarm_subscription" {
  topic_arn = aws_sns_topic.lambda_alarm_topic.arn
  protocol  = "email"
  endpoint  = "your-email@example.com" # Replace with your email address
}


resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_exec_role.arn
}
