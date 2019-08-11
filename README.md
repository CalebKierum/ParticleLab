# Particle Lab Refactored

Awhile back FlexMonkey developed a particle system that could simulate a few million particles for a multi-touhch display at 40fps. However this original version has not been updated to more modern versions of metal. Additionally the original version had synchronization issues that caused flickering and other artifacts.

I have refactored and revamped the original version adding in my own version of "Glow" mode, fixing synchronization issues, and ultimately making many sections run faster. I have also caused particles that are large distances out to respawn. Force touch also now changes the strength of the gravity wells.

To do this I had to make some changes to the comupte shader simulating the particles, large changes to the core engine and data structures, and of course added in some additional post processing logic.

## Results

### Glow Mode
![Screenshot](https://i.imgur.com/z5sQmjm.png) 

Glow mode is achieved through my <blur composition> method allowing you to composite a complex blur over your scene.

### Cloud Mode

 ![Screenshot](https://i.imgur.com/dXTb7CQ.png) 

This effect is achieved by consistently blurring the image then using a min filter to pull in darker colors creating the effect of wisps.

### Video of it in action

[![](http://img.youtube.com/vi/gOqDZfU0EmU/0.jpg)](http://www.youtube.com/watch?v=gOqDZfU0EmU "Play Here")
