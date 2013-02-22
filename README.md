ebsvol
======

This puppet module allows you to create and attach amazon ebs volumes to EC2 instances using Puppet.

* Create or destroy ebsvolumes identified by their 'Name' tag.
* Specify the size in GB (used when creating a new one)
* Volumes are created in the availability_zone that you specify or the same availability zone as the node which defines it..
* Attach the volume to an EC2 instance with a specific 'Name' tag using attached_to.
* Attach the volume to instance doing the puppet run by specifying attached_to 'me'
* Choose which device to attach to (required when attaching)

More details are at http://www.practicalclouds.com/content/guide/pclouds-ebsvol-provision-ebs-volumes-through-puppet

License
-------

 Copyright 2011 David McCormick

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

        http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.

Contact
-------

dave(at)practicalclouds.com

Support
-------

Please log tickets and issues at our [Projects site](http://github.com/practicalclouds/pclouds-ebsvol/issues)

