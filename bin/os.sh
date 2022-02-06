#!/bin/bash 

uname | awk '{print tolower($0)}'