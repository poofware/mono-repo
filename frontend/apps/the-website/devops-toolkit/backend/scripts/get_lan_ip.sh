#!/bin/bash

echo $(ip route get 1.1.1.1 | awk '{print $7}' | head -1)
