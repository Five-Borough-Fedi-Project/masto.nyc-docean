#!/bin/bash
# This modifies all the replicasets in the instance of an upgrade.
# this is a lazy way to do it, but it works.

if [ $1 == "prepare" ];
then
    kubectl --namespace mastodon scale deployment mastodon-web --replicas=0
    kubectl --namespace mastodon scale deployment mastodon-sidekiq-default --replicas=0
    kubectl --namespace mastodon scale deployment mastodon-sidekiq-ingress --replicas=0
    kubectl --namespace mastodon scale deployment mastodon-sidekiq-mailers --replicas=0
    kubectl --namespace mastodon scale deployment mastodon-sidekiq-pull --replicas=0
    kubectl --namespace mastodon scale deployment mastodon-sidekiq-push --replicas=0
    kubectl --namespace mastodon scale deployment mastodon-streaming --replicas=0
    echo "all mastodon deployments except scheduler scaled to 0"
fi

if [ $1 == "drain" ];
then
    kubectl --namespace mastodon scale deployment mastodon-web --replicas=0
    kubectl --namespace mastodon scale deployment mastodon-sidekiq-default --replicas=0
    kubectl --namespace mastodon scale deployment mastodon-sidekiq-ingress --replicas=0
    kubectl --namespace mastodon scale deployment mastodon-sidekiq-mailers --replicas=0
    kubectl --namespace mastodon scale deployment mastodon-sidekiq-pull --replicas=0
    kubectl --namespace mastodon scale deployment mastodon-sidekiq-push --replicas=0
    kubectl --namespace mastodon scale deployment mastodon-streaming --replicas=0
    kubectl --namespace mastodon scale deployment mastodon-sidekiq-sched --replicas=0
    echo "all mastodon deployments scaled to 0"
fi

if [ $1 == "fill" ];
then
    kubectl --namespace mastodon scale deployment mastodon-web --replicas=1
    kubectl --namespace mastodon scale deployment mastodon-sidekiq-default --replicas=1
    kubectl --namespace mastodon scale deployment mastodon-sidekiq-ingress --replicas=1
    kubectl --namespace mastodon scale deployment mastodon-sidekiq-mailers --replicas=1
    kubectl --namespace mastodon scale deployment mastodon-sidekiq-pull --replicas=1
    kubectl --namespace mastodon scale deployment mastodon-sidekiq-push --replicas=1
    kubectl --namespace mastodon scale deployment mastodon-streaming --replicas=1
    kubectl --namespace mastodon scale deployment mastodon-sidekiq-sched --replicas=1
    echo "all mastodon deployments scaled to 1"
fi