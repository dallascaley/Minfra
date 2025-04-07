# Minfra

Here's some stuff about this thing...

main-vpc created, Visible here:

  https://us-west-2.console.aws.amazon.com/vpcconsole/home?region=us-west-2#vpcs:

subnet-a created, Visible here:

  https://us-west-2.console.aws.amazon.com/vpcconsole/home?region=us-west-2#subnets:

main-igw created, Visible here:

  https://us-west-2.console.aws.amazon.com/vpcconsole/home?region=us-west-2#igws:

Route Tables:

  https://us-west-2.console.aws.amazon.com/vpcconsole/home?region=us-west-2#RouteTables:

General Notes:

At the moment, this thing doesn't work, but everything seems to be working.  By that, I mean you can go ahead and 
terraform apply and it all spins up fine, but no site.  

Possible reasons why?

I suspect the Docker instance does not load correctly.  Seems like there should be some sort of key or something 
placed into the newly created box that would allow it to get the container from the Docker Hub

How can we test this?
