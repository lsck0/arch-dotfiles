const translations = {
  ru: {
    myProfile: "Мой профиль",
    activities: "Активности",
    inventory: "Инвентарь"
  },
  en: {
    myProfile: "View my profile",
    activities: "Activities",
    inventory: "Inventory"
  },
  es: {
    myProfile: "Ver mi perfil",
    activities: "Actividades",
    inventory: "Inventario"
  },
  de: {
    myProfile: "Mein Profil",
    activities: "Aktivitäten",
    inventory: "Inventar"
  },
  fr: {
    myProfile: "Afficher mon profil",
    activities: "Activités",
    inventory: "Inventaire"
  },
  it: {
    myProfile: "Il Mio Profilo",
    activities: "Attività",
    inventory: "Inventario"
  },
  pt: {
    myProfile: "Meu Perfil",
    activities: "Atividades",
    inventory: "Inventário"
  },
  ja: {
    myProfile: "プロフィールを表示",
    activities: "アクティビティ",
    inventory: "インベントリ"
  },
  ko: {
    myProfile: "내 프로필 보기",
    activities: "활동",
    inventory: "인벤토리"
  },
  zh: {
    myProfile: "查看我的个人资料",
    activities: "动态",
    inventory: "库存"
  },
  nl: {
    myProfile: "Mijn Profiel",
    activities: "Activiteiten",
    inventory: "Inventaris"
  },
  pl: {
    myProfile: "Mój Profil",
    activities: "Aktywności",
    inventory: "Ekwipunek"
  },
  sv: {
    myProfile: "Vis min profil",
    activities: "Aktiviteter",
    inventory: "Inventarium"
  },
  da: {
    myProfile: "Min Profil",
    activities: "Aktiviteter",
    inventory: "Inventar"
  },
  fi: {
    myProfile: "Oma Profiili",
    activities: "Aktiviteetit",
    inventory: "Tavaraluettelo"
  },
  no: {
    myProfile: "Min Profil",
    activities: "Aktiviteter",
    inventory: "Inventar"
  },
  hu: {
    myProfile: "Profilom",
    activities: "Tevékenységek",
    inventory: "Leltár"
  },
  cs: {
    myProfile: "Můj profil",
    activities: "Aktivity",
    inventory: "Inventář"
  },
  ro: {
    myProfile: "Profilul Meu",
    activities: "Activități",
    inventory: "Inventar"
  },
  tr: {
    myProfile: "Profilim",
    activities: "Etkinlikler",
    inventory: "Envanter"
  },
  el: {
    myProfile: "Προβολή του προφίλ μου",
    activities: "Δραστηριότητες",
    inventory: "Αποθήκη"
  },
  bg: {
    myProfile: "Преглед на профила ми",
    activities: "Дейности",
    inventory: "Инвентар"
  },
  uk: {
    myProfile: "Переглянути профіль",
    activities: "Активності",
    inventory: "Інвентар"
  },
  th: {
    myProfile: "ดูโปรไฟล์ของฉัน",
    activities: "กิจกรรม",
    inventory: "คลังไอเทม"
  },
  vi: {
    myProfile: "Hồ Sơ Của Tôi",
    activities: "Hoạt Động",
    inventory: "Kho Đồ"
  },
  id: {
    myProfile: "Lihat profil saya",
    activities: "Aktivitas",
    inventory: "Inventaris"
  }
};

function getCurrentLanguage() {
  let lang = document.documentElement.lang;
  
  if (!lang) {
    const metaLang = document.querySelector('meta[name="language"]');
    if (metaLang) {
      lang = metaLang.getAttribute('content');
    }
  }
  
  if (!lang) {
    lang = navigator.language || navigator.userLanguage;
  }
  
  return lang.split('-')[0];
}

function getTranslation(lang, key) {
  return (translations[lang] && translations[lang][key]) || translations.en[key];
}

function removeExistingMyProfileButton() {
  const existingButtons = document.getElementsByClassName('_2jXHP0742MyApMUVUM8IFn');
  const profileTexts = Object.values(translations).map(lang => lang.myProfile);
  
  for (let i = 0; i < existingButtons.length; i++) {
    if (profileTexts.includes(existingButtons[i].textContent.trim())) {
      existingButtons[i].remove();
      break;
    }
  }
}

function createMyProfileButton() {
  const myProfileButton = main_acc.cloneNode(true);
  myProfileButton.addEventListener('click', function(event) {
    event.preventDefault();
    window.location = 'steam://url/SteamIDMyProfile';
  });
  return myProfileButton;
}

function setLanguage() {
  const currentLang = getCurrentLanguage();
  my_profile_button.innerHTML = getTranslation(currentLang, 'myProfile');
  main_acc.innerHTML = getTranslation(currentLang, 'activities');
  inventory_button.innerHTML = getTranslation(currentLang, 'inventory');
}

let main = document.getElementsByClassName("HoGkIKTQnkTEFGjqO-GMl");
let main_acc = document.getElementsByClassName('_2jXHP0742MyApMUVUM8IFn')[0].cloneNode(true);
let hr_acc = document.getElementsByClassName('_2jXHP0742MyApMUVUM8IFn')[4].cloneNode(true);
let inventory_button = main_acc.cloneNode(true);
let my_profile_button = createMyProfileButton();

removeExistingMyProfileButton();
setLanguage();

main_acc.addEventListener('click', function(event) {
    event.preventDefault();
    window.location = 'steam://url/SteamIDFriendsPage';
});

inventory_button.addEventListener('click', function(event) {
    event.preventDefault();
    window.location = 'steam://url/CommunityInventory';
});

main[0].insertBefore(hr_acc, main[0].firstElementChild);
main[0].insertBefore(inventory_button, main[0].firstElementChild);
main[0].insertBefore(main_acc, main[0].firstElementChild);
main[0].insertBefore(my_profile_button, main[0].firstElementChild);

document.addEventListener('languagechange', setLanguage);

function changeLanguage(lang) {
  document.documentElement.lang = lang;
  setLanguage();
}

let driver = document.getElementById('driver');
if (driver && driver.parentNode) {
    driver.parentNode.appendChild(driver);
}

