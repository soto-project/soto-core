struct AutoscalingResponseModule {
    static let describeAutoscalingGroups = """
    {
      "DescribeAutoScalingGroupsResponse" : {
        "DescribeAutoScalingGroupsResult" : {
          "AutoScalingGroups" : {
            "Member" : {
              "DefaultCooldown" : 300,
              "ServiceLinkedRoleARN" : "arn:aws:iam::427300000128:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling",
              "Tags" : {
                "Member" : [
                  {
                    "PropagateAtLaunch" : true,
                    "Value" : "fake-asg",
                    "ResourceType" : "auto-scaling-group",
                    "ResourceId" : "fake-asg",
                    "Key" : "AsgName"
                  },
                  {
                    "PropagateAtLaunch" : true,
                    "Value" : false,
                    "ResourceType" : "auto-scaling-group",
                    "ResourceId" : "fake-asg",
                    "Key" : "DedicatedInstance"
                  },
                  {
                    "PropagateAtLaunch" : true,
                    "Value" : "fake-launch-configuration",
                    "ResourceType" : "auto-scaling-group",
                    "ResourceId" : "fake-asg",
                    "Key" : "LaunchConfigName"
                  }
                ]
              },
              "TargetGroupARNs" : null,
              "CreatedTime" : "2018-04-23T21:29:08.430Z",
              "MinSize" : 0,
              "HealthCheckType" : "EC2",
              "AvailabilityZones" : {
                "Member" : [
                  "us-east-1a",
                  "us-east-1b",
                  "us-east-1d",
                  "us-east-1e"
                ]
              },
              "DesiredCapacity" : 1,
              "AutoScalingGroupARN" : "arn:aws:autoscaling:us-east-1:427300000128:autoScalingGroup:0a2943e3-29d5-4fd8-9f77-36928e569123:autoScalingGroupName/fake-asg",
              "EnabledMetrics" : {
                "Member" : [
                  {
                    "Granularity" : "1Minute",
                    "Metric" : "GroupMaxSize"
                  },
                  {
                    "Granularity" : "1Minute",
                    "Metric" : "GroupStandbyInstances"
                  },
                  {
                    "Granularity" : "1Minute",
                    "Metric" : "GroupTotalInstances"
                  },
                  {
                    "Granularity" : "1Minute",
                    "Metric" : "GroupDesiredCapacity"
                  },
                  {
                    "Granularity" : "1Minute",
                    "Metric" : "GroupTerminatingInstances"
                  },
                  {
                    "Granularity" : "1Minute",
                    "Metric" : "GroupPendingInstances"
                  },
                  {
                    "Granularity" : "1Minute",
                    "Metric" : "GroupMinSize"
                  },
                  {
                    "Granularity" : "1Minute",
                    "Metric" : "GroupInServiceInstances"
                  }
                ]
              },
              "HealthCheckGracePeriod" : 300,
              "LoadBalancerNames" : null,
              "Instances" : {
                "Member" : {
                  "HealthStatus" : "Healthy",
                  "LifecycleState" : "InService",
                  "InstanceId" : "i-00cc1146a6a3986d9",
                  "ProtectedFromScaleIn" : false,
                  "AvailabilityZone" : "us-east-1a"
                }
              },
              "MaxSize" : 10,
              "VPCZoneIdentifier" : "subnet-203b5457,subnet-a3a99cbb,subnet-128f3b49,subnet-54e4b6cc",
              "TerminationPolicies" : {
                "Member" : "OldestInstance"
              },
              "LaunchConfigurationName" : "fake-launch-configuration",
              "AutoScalingGroupName" : "fake-asg",
              "NewInstancesProtectedFromScaleIn" : false,
              "SuspendedProcesses" : null
            }
          }
        },
        "ResponseMetadata" : {
          "RequestId" : "117255af-7a2f-10e8-b9d6-c172a21cfccd"
        }
      }
    }
    """
}
