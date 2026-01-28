// User dropdown functionality
document.addEventListener('DOMContentLoaded', function() {
  // Find all dropdown buttons and menus
  const dropdownButtons = document.querySelectorAll('[id="user-menu-button"]');
  const dropdownMenus = document.querySelectorAll('[id="user-menu-dropdown"]');

  // Initialize dropdowns for each button/menu pair
  dropdownButtons.forEach((button, index) => {
    const menu = dropdownMenus[index];

    if (button && menu) {
      // Toggle dropdown on button click
      button.addEventListener('click', function() {
        const isVisible = !menu.classList.contains('invisible');

        // Close all other dropdowns first
        dropdownMenus.forEach((otherMenu, otherIndex) => {
          if (otherIndex !== index) {
            otherMenu.classList.add('invisible');
            otherMenu.classList.add('opacity-0');
            otherMenu.classList.add('scale-95');
            otherMenu.classList.remove('opacity-100');
            otherMenu.classList.remove('scale-100');
          }
        });

        if (isVisible) {
          // Hide this dropdown
          menu.classList.add('invisible');
          menu.classList.add('opacity-0');
          menu.classList.add('scale-95');
        } else {
          // Show this dropdown
          menu.classList.remove('invisible');
          menu.classList.remove('opacity-0');
          menu.classList.remove('scale-95');
          menu.classList.add('opacity-100');
          menu.classList.add('scale-100');
        }
      });
    }
  });

  // Close dropdowns when clicking outside
  document.addEventListener('click', function(event) {
    let clickedInsideDropdown = false;

    dropdownButtons.forEach((button, index) => {
      const menu = dropdownMenus[index];
      if (button && menu) {
        if (button.contains(event.target) || menu.contains(event.target)) {
          clickedInsideDropdown = true;
        }
      }
    });

    if (!clickedInsideDropdown) {
      dropdownMenus.forEach(menu => {
        menu.classList.add('invisible');
        menu.classList.add('opacity-0');
        menu.classList.add('scale-95');
        menu.classList.remove('opacity-100');
        menu.classList.remove('scale-100');
      });
    }
  });
});
