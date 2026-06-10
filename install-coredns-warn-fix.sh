#!/bin/bash

helm upgrade --install --rollback-on-failure coredns-warn-fix ./coredns-warn-fix
